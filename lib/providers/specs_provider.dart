import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/telemetry_service.dart';
import '../services/window_service.dart';
import '../services/vault_service.dart';

export 'package:zenit_flutter/services/vault_service.dart' show VideoMeta;
export 'retail_theme.dart';

enum RetailStore { none, falabella, paris, ripley }

class SpecsProvider extends ChangeNotifier {
  final TelemetryService _telemetry = TelemetryService();
  final WindowService _window = WindowService();
  final VaultService _vault = VaultService();

  Map<String, dynamic> _currentSpecs = {};
  Map<String, dynamic> _autoDetectedSpecs = {};
  List<VideoMeta> _savedVideos = [];
  bool _isLoading = true;
  bool _isVideoMode = false;
  bool _isModalOpen = false;
  RetailStore _store = RetailStore.none;

  Timer? _inAppInactivityTimer;
  static const int inAppInactivityLimitMs = 180000; // 3 minutos

  Map<String, dynamic> get currentSpecs => _currentSpecs;
  Map<String, dynamic> get autoDetectedSpecs => _autoDetectedSpecs;
  List<VideoMeta> get savedVideos => _savedVideos;
  bool get isLoading => _isLoading;
  bool get isVideoMode => _isVideoMode;
  bool get isModalOpen => _isModalOpen;
  RetailStore get store => _store;
  bool get isFloatingMode => _window.isFloatingMode;

  WindowService get windowService => _window;
  VaultService get vaultService => _vault;

  // Mapeo de alias de videos internos a sus assets en Flutter
  static const Map<String, String> videoAliases = {
    '__ASUS_PROMO__': 'assets/videos/promo-asus.mp4',
    '__GENERIC_PROMO__': 'assets/videos/promo-generic.mp4',
    '__ASUS_LANDING__': 'assets/videos/landing-asus.mp4',
    '__GENERIC_LANDING__': 'assets/videos/landing-generic.mp4',
    '__GAMING_XBOX__': 'assets/videos/gaming_xbox_game_pass.mp4',
    '__WINDOWS_GAMING__': 'assets/videos/windows_the_home_of_gaming.mp4',
    '__QUALITY_DURABILITY__': 'assets/videos/BUILT-TO-LAST-Quality-and-Durability.mp4',
    '__TUF_DURABILITY__': 'assets/videos/Quality_and_Durability_TUF_Gaming.mp4',
    '__ASUS_WARRANTY__': 'assets/videos/Asus_Garantia_Perfecta.mp4',
    'ASUS': 'assets/videos/background-asus.mp4',
    'GENERIC': 'assets/videos/background-generic.mp4',
  };

  bool get isAsus {
    final b = (_currentSpecs['brand'] ?? '').toString().toLowerCase();
    final m = (_currentSpecs['model'] ?? '').toString().toLowerCase();
    return b.contains('asus') || m.contains('asus');
  }

  bool get isRTX {
    final g = (_currentSpecs['gpu'] ?? '').toString().toLowerCase();
    return g.contains('rtx');
  }

  bool get isGeneric {
    final b = (_currentSpecs['brand'] ?? '').toString().toLowerCase();
    return !isAsus || b.contains('generico');
  }

  // --- INICIALIZACIÓN ---

  Future<void> loadSpecs() async {
    _isLoading = true;
    notifyListeners();

    // 1. Inicializar servicios locales
    _vault.initialize();
    _window.initialize();

    try {
      // 2. Cargar specs guardados del store.json
      final stored = await _vault.loadSpecsFromStore();
      if (stored.containsKey('store')) {
        _updateStoreEnum(stored['store']);
      }

      // 3. Ejecutar escaneo de hardware nativo
      final detected = await _telemetry.getSystemSpecs();
      _autoDetectedSpecs = detected.toJson();

      // 4. Fusionar datos (Prevalece lo guardado en store sobre lo detectado)
      _currentSpecs = {..._autoDetectedSpecs, ...stored};

      // Si es el primer inicio y no hay nada en disco, inicializar defaults
      if (stored.isEmpty) {
        _currentSpecs['firstStartCompleted'] = false;
        _currentSpecs['store'] = 'none';
        _currentSpecs['adminPassword'] = 'demo';
        _currentSpecs['videoType'] = 'default';
        _currentSpecs['landingVideoType'] = 'default';
        _currentSpecs['showAsusWarrantyTicker'] = false;
        _currentSpecs['storeBadge'] = 'none';
        
        // Slots vacíos
        _currentSpecs['customVideoPaths'] = [
          {'name': '', 'path': ''},
          {'name': '', 'path': ''},
          {'name': '', 'path': ''}
        ];
      }

      // 5. Autoselección inteligente de videos por marca y GPU
      _initializeSmartVideoDefaults();

      // 6. Cargar la lista de videos subidos a la bóveda
      _savedVideos = await _vault.listCustomVideos();

      // 7. Limpiar huérfanos
      await _vault.cleanupOrphanVideos();
    } catch (e) {
      debugPrint('[SpecsProvider] Error al cargar especificaciones: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      resetInAppActivityTimer();
    }
  }

  void _updateStoreEnum(String? storeName) {
    final s = (storeName ?? 'none').toLowerCase();
    switch (s) {
      case 'falabella': _store = RetailStore.falabella; break;
      case 'paris': _store = RetailStore.paris; break;
      case 'ripley': _store = RetailStore.ripley; break;
      case 'none':
      default:
        _store = RetailStore.none;
    }
  }

  void _initializeSmartVideoDefaults() {
    final isAsusBrand = isAsus;
    final isRtxGpu = isRTX;

    // Default de Landing (Home)
    if (_currentSpecs['customLandingVideoPath'] == null) {
      if (isRtxGpu) {
        _currentSpecs['customLandingVideoPath'] = '__GAMING_XBOX__';
        _currentSpecs['customLandingVideoName'] = 'Xbox Game Pass (Gaming)';
      } else {
        _currentSpecs['customLandingVideoPath'] = '__GENERIC_LANDING__';
        _currentSpecs['customLandingVideoName'] = 'Original Windows 11 (Home)';
      }
    }

    // Default de Slots de Inactividad (Screensaver)
    final List<dynamic> slots = _currentSpecs['customVideoPaths'] ?? [];
    final hasAnyCustomSet = slots.any((s) => (s['path'] ?? '').isNotEmpty);
    if (!hasAnyCustomSet) {
      if (isRtxGpu && isAsusBrand) {
        slots[0] = {'name': 'TUF Gaming: Durabilidad', 'path': '__TUF_DURABILITY__'};
        slots[1] = {'name': 'Promo Asus', 'path': '__ASUS_PROMO__'};
      } else if (isRtxGpu) {
        slots[0] = {'name': 'Windows Gaming', 'path': '__WINDOWS_GAMING__'};
      } else if (isAsusBrand) {
        slots[0] = {'name': 'Promo Genérica', 'path': '__GENERIC_PROMO__'};
        slots[1] = {'name': 'Promo Asus', 'path': '__ASUS_PROMO__'};
      } else {
        slots[0] = {'name': 'Promo Genérica', 'path': '__GENERIC_PROMO__'};
      }
      _currentSpecs['customVideoPaths'] = slots;
    }
  }

  // --- LÓGICA DE NEGOCIO ---

  Future<void> saveCustom(Map<String, dynamic> specs) async {
    _currentSpecs = {..._currentSpecs, ...specs};
    
    // Sanitizar SKU a sólo números si existe
    if (_currentSpecs['sku'] != null) {
      _currentSpecs['sku'] = _currentSpecs['sku'].toString().replaceAll(RegExp(r'\D'), '');
    }

    _updateStoreEnum(_currentSpecs['store']);
    await _vault.saveSpecsToStore(_currentSpecs);
    
    notifyListeners();
  }

  void restoreField(String field) {
    _currentSpecs[field] = _autoDetectedSpecs[field] ?? '';
    notifyListeners();
  }

  // Resuelve la URL o el Uri del video para media_kit
  String resolveVideoUri(String path) {
    if (videoAliases.containsKey(path)) {
      return 'asset://${videoAliases[path]}';
    }
    if (path.startsWith('assets/')) {
      return 'asset://$path';
    }
    // De lo contrario, es una ruta de archivo absoluta a custom-videos/... (Bóveda)
    return path;
  }

  // Recupera los paths de videos de inactividad que están configurados y no vacíos
  List<String> getActiveScreensaverPaths() {
    final List<dynamic> slots = _currentSpecs['customVideoPaths'] ?? [];
    final paths = <String>[];
    for (var slot in slots) {
      final String path = slot['path'] ?? '';
      if (path.isNotEmpty) {
        paths.add(resolveVideoUri(path));
      }
    }
    // Si la lista está vacía (seguridad), usar fallbacks según marca
    if (paths.isEmpty) {
      paths.add(resolveVideoUri(isAsus ? '__ASUS_PROMO__' : '__GENERIC_PROMO__'));
    }
    return paths;
  }

  // --- MODAL & VIDEO MANAGEMENT ---

  set isModalOpen(bool open) {
    _isModalOpen = open;
    if (open) {
      _inAppInactivityTimer?.cancel();
    } else {
      resetInAppActivityTimer();
    }
    notifyListeners();
  }

  set isVideoMode(bool active) {
    _isVideoMode = active;
    if (active) {
      // Activar brillo al máximo al entrar a screensaver
      _window.preventSleep();
    } else {
      resetInAppActivityTimer();
    }
    notifyListeners();
  }

  // --- LÓGICA DE INACTIVIDAD IN-APP ---

  void resetInAppActivityTimer() {
    if (_isModalOpen) return;

    _inAppInactivityTimer?.cancel();
    
    if (_isVideoMode) {
      _isVideoMode = false;
      notifyListeners();
    }

    _inAppInactivityTimer = Timer(const Duration(milliseconds: inAppInactivityLimitMs), () {
      // Al expirar el tiempo de inactividad interno, cerrar modales y entrar a screensaver
      _isModalOpen = false;
      _isVideoMode = true;
      notifyListeners();
    });
  }

  // Invoca el watchdog de inactividad de Windows (cuando se minimiza)
  void minimizeKioskWithOSWatchdog() {
    _window.enterFloatingMode();
    
    // Iniciar el monitor Win32 a nivel del SO
    _window.startSystemIdleMonitor(
      idleLimitMs: inAppInactivityLimitMs,
      onIdleTriggered: () {
        // Al dispararse por inactividad de OS, re-maximizar y poner screensaver
        _isVideoMode = true;
        notifyListeners();
      },
      onActivity: () {
        // Si detecta actividad física tras la restauración
        _isVideoMode = false;
        notifyListeners();
      },
    );
  }

  void restoreKiosk() {
    _window.stopSystemIdleMonitor();
    _window.restoreKioskMode();
    resetInAppActivityTimer();
  }

  @override
  void dispose() {
    _inAppInactivityTimer?.cancel();
    _window.dispose();
    super.dispose();
  }
}
