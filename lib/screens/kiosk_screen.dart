import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../providers/specs_provider.dart';
import '../widgets/admin_modal.dart';
import '../widgets/first_start_modal.dart';
import '../widgets/password_modal.dart';
import '../widgets/screensaver_player.dart';
import '../widgets/specs_modal.dart';

class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key});

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  // Reproductores nativos para la vista principal
  late final Player _bgPlayer;
  late final Player _landingPlayer;
  late final VideoController _bgController;
  late final VideoController _landingController;

  bool _playersInitialized = false;
  bool _showWarrantyOverlay = false;

  // Seguimiento de clics para los Hotspots ocultos
  int _settingsClicks = 0;
  int _exitClicks = 0;
  DateTime? _lastSettingsClick;
  DateTime? _lastExitClick;

  @override
  void initState() {
    super.initState();
    _bgPlayer = Player();
    _landingPlayer = Player();
    _bgController = VideoController(_bgPlayer);
    _landingController = VideoController(_landingPlayer);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startKioskVideos();
    });
  }

  void _startKioskVideos() {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    
    final bgPath = provider.resolveVideoUri(provider.isAsus ? 'ASUS' : 'GENERIC');
    final landingPath = provider.resolveVideoUri(provider.currentSpecs['customLandingVideoPath'] ?? (provider.isAsus ? '__ASUS_LANDING__' : '__GENERIC_LANDING__'));

    _bgPlayer.open(Media(bgPath));
    _bgPlayer.setPlaylistMode(PlaylistMode.loop);
    _bgPlayer.setVolume(0.0); // Silenciar

    _landingPlayer.open(Media(landingPath));
    _landingPlayer.setPlaylistMode(PlaylistMode.loop);
    _landingPlayer.setVolume(0.0); // Silenciar

    setState(() {
      _playersInitialized = true;
    });
  }

  // Pausar reproductores para liberar recursos GPU
  void _pauseVideos() {
    _bgPlayer.pause();
    _landingPlayer.pause();
  }

  // Reanudar reproducción
  void _resumeVideos() {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    if (!provider.isModalOpen && !provider.isVideoMode && !provider.isFloatingMode) {
      _bgPlayer.play();
      _landingPlayer.play();
    }
  }

  void _handleHotspotClick(String mode) {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    if (provider.isModalOpen) return;

    final now = DateTime.now();
    if (mode == 'settings') {
      if (_lastSettingsClick == null || now.difference(_lastSettingsClick!) > const Duration(seconds: 2)) {
        _settingsClicks = 1;
      } else {
        _settingsClicks++;
      }
      _lastSettingsClick = now;

      if (_settingsClicks >= 4) {
        _settingsClicks = 0;
        _showPasswordPrompt('settings');
      }
    } else {
      if (_lastExitClick == null || now.difference(_lastExitClick!) > const Duration(seconds: 2)) {
        _exitClicks = 1;
      } else {
        _exitClicks++;
      }
      _lastExitClick = now;

      if (_exitClicks >= 4) {
        _exitClicks = 0;
        _showPasswordPrompt('exit');
      }
    }
  }

  void _showPasswordPrompt(String mode) {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    provider.isModalOpen = true;
    _pauseVideos();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PasswordModal(
        mode: mode,
        onClose: () {
          Navigator.of(context).pop();
          provider.isModalOpen = false;
          _resumeVideos();
        },
        onVerified: () {
          Navigator.of(context).pop();
          if (mode == 'exit') {
            provider.windowService.closeApp();
          } else {
            _showAdminPanel();
          }
        },
      ),
    );
  }

  void _showAdminPanel() {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AdminModal(
        onClose: () {
          Navigator.of(context).pop();
          provider.isModalOpen = false;
          // Recargar videos por si cambiaron de asignación
          final bgPath = provider.resolveVideoUri(provider.isAsus ? 'ASUS' : 'GENERIC');
          final landingPath = provider.resolveVideoUri(provider.currentSpecs['customLandingVideoPath'] ?? (provider.isAsus ? '__ASUS_LANDING__' : '__GENERIC_LANDING__'));
          _bgPlayer.open(Media(bgPath));
          _landingPlayer.open(Media(landingPath));
          _resumeVideos();
        },
      ),
    );
  }

  void _showSpecsDetail() {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    provider.isModalOpen = true;
    _pauseVideos();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => SpecsModal(
        onClose: () {
          Navigator.of(context).pop();
          provider.isModalOpen = false;
          _resumeVideos();
        },
      ),
    );
  }

  @override
  void dispose() {
    _bgPlayer.dispose();
    _landingPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SpecsProvider>(context);
    
    // 0. Si está en modo flotante de retorno, mostrar UI simplificada flotante
    if (provider.isFloatingMode) {
      return _buildFloatingReturnWindow(provider);
    }

    // 1. Mostrar pantalla de carga
    if (provider.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF111111),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF00F2AA)),
              SizedBox(height: 20),
              Text(
                'Cargando especificaciones...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Si primer inicio no se completó, forzar primer asistente
    final specs = provider.currentSpecs;
    if (specs['firstStartCompleted'] == false) {
      return FirstStartModal(
        onCompleted: () {
          provider.resetInAppActivityTimer();
          _resumeVideos();
        },
      );
    }

    // 3. Si está en modo video (Screensaver), mostrar reproductor de inactividad
    if (provider.isVideoMode) {
      _pauseVideos();
      return const ScreensaverPlayer();
    }

    // Asegurar que los videos se reproduzcan si regresamos a la pantalla de specs
    _resumeVideos();

    final theme = RetailTheme.of(provider.store);

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: Listener(
        // Interceptar actividad in-app para reiniciar timer
        onPointerDown: (_) => provider.resetInAppActivityTimer(),
        onPointerHover: (_) => provider.resetInAppActivityTimer(),
        onPointerSignal: (_) => provider.resetInAppActivityTimer(),
        child: KeyboardListener(
          focusNode: FocusNode(),
          autofocus: true,
          onKeyEvent: (_) => provider.resetInAppActivityTimer(),
          child: Stack(
            children: [
              // --- FONDO: Imagen estática con patrón ---
              SizedBox.expand(
                child: Image.asset(
                  provider.isAsus ? 'assets/images/background-asus.png' : 'assets/images/background-generic.png',
                  fit: BoxFit.cover,
                ),
              ),
              // Video Loop de Fondo
              if (_playersInitialized)
                SizedBox.expand(
                  child: Video(
                    controller: _bgController,
                    fit: BoxFit.cover,
                    controls: NoVideoControls,
                  ),
                ),
              // Capa de Overlay Gradiente (Retail)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.gradientStart,
                        theme.gradientEnd,
                      ],
                    ),
                  ),
                ),
              ),

              // --- LAYOUT PRINCIPAL (proporciones basadas en pantalla) ---
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final sw = constraints.maxWidth;
                    final sh = constraints.maxHeight;
                    final hPad = sw * 0.05;   // 5% margen lateral
                    final vPad = sh * 0.04;   // 4% margen vertical
                    final colGap = sw * 0.025; // ~2.5% gap entre columnas

                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header: ~10% de la altura
                          SizedBox(
                            height: sh * 0.09,
                            child: _buildHeader(provider, theme),
                          ),
                          SizedBox(height: sh * 0.02),
                          // Cuerpo principal: 90% restante
                          Expanded(
                            child: Row(
                              // CrossAxisAlignment.start: el top del video alineado con la primera tarjeta
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Izquierda: ~35% del ancho total → flex 7
                                Expanded(
                                  flex: 7,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: _buildSpecsGrid(provider, theme)),
                                      SizedBox(height: sh * 0.015),
                                      _buildCtaButton(provider, theme),
                                    ],
                                  ),
                                ),
                                SizedBox(width: colGap),
                                // Derecha: ~60% del ancho total → flex 12
                                Expanded(
                                  flex: 12,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _buildLandingVideoBox(provider, theme),
                                      // Botón Garantía Perfecta (solo ASUS con opción activa)
                                      if (provider.isAsus && provider.currentSpecs['showAsusWarrantyTicker'] == true) ...[
                                        SizedBox(height: sh * 0.012),
                                        _buildWarrantyTriggerButton(theme),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // --- HOTSPOTS INVISIBLES DE SEGURIDAD ---
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => _handleHotspotClick('settings'),
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox(width: 90, height: 90),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => _handleHotspotClick('exit'),
                  behavior: HitTestBehavior.translucent,
                  child: const SizedBox(width: 90, height: 90),
                ),
              ),

              // Watermark
              const Positioned(
                bottom: 8,
                left: 15,
                child: Text(
                  'Developed by Juan Marchant',
                  style: TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- SUB WIDGETS DE LA UI ---

  Widget _buildHeader(SpecsProvider provider, RetailTheme theme) {
    final brand = (provider.currentSpecs['brand'] ?? '').toString().toLowerCase();

    // Logo de marca usando SVGs de Zenit-Tauri
    Widget brandLogo;
    if (brand.contains('asus')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-asus.svg',
        height: 32,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('hp') || brand.contains('hewlett')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-hp.svg',
        height: 32,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('lenovo')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-lenovo.svg',
        height: 28,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('acer')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-acer.svg',
        height: 28,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('samsung')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-samsung.svg',
        height: 28,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('dell')) {
      brandLogo = Text('DELL',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2));
    } else if (brand.contains('microsoft')) {
      brandLogo = Text('SURFACE',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5));
    } else {
      brandLogo = Text(
        brand.isNotEmpty ? brand.toUpperCase() : 'ZENIT',
        style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Logos izquierda: Marca + tienda (Flexible para no desbordarse)
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              brandLogo,
              // Logo Retail al lado si hay tienda configurada
              if (theme.logoAsset != null) ...[
                const SizedBox(width: 12),
                Container(
                  width: 1,
                  height: 24,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 12),
                theme.storeLogoWidget,
              ],
            ],
          ),
        ),

        // Badge de tienda a la derecha (solo si hay tienda)
        if (theme.logoAsset != null || theme.logoPngAsset != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              provider.store.name.toUpperCase(),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSpecsGrid(SpecsProvider provider, RetailTheme theme) {
    final specs = provider.currentSpecs;
    final processor = specs['processor'] ?? 'Cargando...';
    final gpu = specs['gpu'] ?? 'Cargando...';

    final cards = [
      _buildSpecCard('PROCESADOR', processor, 'assets/images/ui-cpu.svg',
          chipVendor: _detectChipVendor(processor), theme: theme),
      _buildSpecCard('MEMORIA RAM', specs['ram'] ?? 'Cargando...', 'assets/images/ui-ram.svg', theme: theme),
      _buildSpecCard('ALMACENAMIENTO', specs['storage'] ?? 'Cargando...', 'assets/images/ui-storage.svg', theme: theme),
      _buildSpecCard('PANTALLA', specs['display'] ?? 'Cargando...', 'assets/images/ui-display.svg', theme: theme),
      _buildSpecCard('GRÁFICOS', gpu, 'assets/images/ui-gpu.svg',
          chipVendor: _detectChipVendor(gpu), theme: theme),
      _buildSpecCard('SISTEMA OPERATIVO', specs['os'] ?? 'Cargando...', 'assets/images/ui-windows.svg', theme: theme),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: cards.map((c) => Expanded(child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: c,
      ))).toList(),
    );
  }

  /// Detecta el fabricante del chip desde el string del spec
  String? _detectChipVendor(String value) {
    final v = value.toLowerCase();
    if (v.contains('intel')) return 'intel';
    if (v.contains('amd') || v.contains('ryzen') || v.contains('radeon')) return 'amd';
    if (v.contains('nvidia') || v.contains('geforce') || v.contains('rtx') || v.contains('gtx')) return 'nvidia';
    if (v.contains('snapdragon') || v.contains('qualcomm')) return 'snapdragon';
    return null;
  }

  Widget _buildSpecCard(String label, String value, String iconAsset, {
    String? chipVendor,
    required RetailTheme theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12), // Radio 12 según especificación
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icono SVG de la categoria
          SvgPicture.asset(
            iconAsset,
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(Color(0xFF444444), BlendMode.srcIn),
          ),
          const SizedBox(width: 12),
          // Etiqueta + Valor
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          // Logo del fabricante del chip (Intel / AMD / Nvidia)
          if (chipVendor != null) ...[
            const SizedBox(width: 8),
            SvgPicture.asset(
              'assets/images/brand-$chipVendor.svg',
              height: 18,
              colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcIn),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCtaButton(SpecsProvider provider, RetailTheme theme) {
    return GestureDetector(
      onTap: () {
        // Minimizar al modo flotante de prueba para que el cliente use el PC
        _pauseVideos();
        provider.minimizeKioskWithOSWatchdog();
      },
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.primary, theme.primary.withValues(alpha: 0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: theme.primary.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'PRUEBA ESTA PC',
            style: GoogleFonts.outfit(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandingVideoBox(SpecsProvider provider, RetailTheme theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28), // Radio mayor para integrar con el fondo
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            children: [
              // Video Loop del Home en 16:9
              if (_playersInitialized && !_showWarrantyOverlay)
                Positioned.fill(
                  child: Video(
                    controller: _landingController,
                    fit: BoxFit.contain,
                    controls: NoVideoControls,
                  ),
                ),

              // Overlay de Garantia Perfecta ASUS (cubre el video con botón ✕)
              if (_showWarrantyOverlay && provider.isAsus)
                Positioned.fill(
                  child: Stack(
                    children: [
                      _buildASUSWarrantyCard(theme),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => setState(() => _showWarrantyOverlay = false),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.close, color: Colors.white70, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Boton expandir specs (esquina superior derecha)
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen, color: Colors.white, size: 20),
                    tooltip: 'Ver especificaciones detalladas',
                    onPressed: _showSpecsDetail,
                  ),
                ),
              ),

              // Precios superpuestos en la esquina inferior
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildOverlaidPrices(provider, theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlaidPrices(SpecsProvider provider, RetailTheme theme) {
    final specs = provider.currentSpecs;
    final hasPrimary = (specs['pricePrimary'] ?? '').toString().isNotEmpty;
    final hasSecondary = (specs['priceSecondary'] ?? '').toString().isNotEmpty;
    if (!hasPrimary && !hasSecondary) return const SizedBox();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Row(
        children: [
          if (hasPrimary)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('EXCLUSIVO TARJETA', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  // Precio + logo de tarjeta en la misma fila
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        specs['pricePrimary'],
                        style: TextStyle(color: theme.primary, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 10),
                      _buildRetailCardIcon(provider.store),
                    ],
                  ),
                ],
              ),
            ),
          if (hasPrimary && hasSecondary) const SizedBox(width: 16),
          if (hasSecondary)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TODO MEDIO DE PAGO', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    specs['priceSecondary'],
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWarrantyTriggerButton(RetailTheme theme) {
    return GestureDetector(
      onTap: () => setState(() => _showWarrantyOverlay = !_showWarrantyOverlay),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, color: theme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Ver Garantía Perfecta',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildASUSWarrantyCard(RetailTheme theme) {
    return Container(
      color: const Color(0xFF111111).withValues(alpha: 0.97),
      padding: const EdgeInsets.all(22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Columna Izquierda: info ---
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título
                const Text(
                  'Garantía Perfecta ASUS',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'ASUS ofrece un año de Garantía Perfecta (protección complementaria contra daños accidentales) en ciertos productos. Complete el registro dentro de los primeros 90 días posteriores a la compra.',
                  style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 10, height: 1.5),
                ),
                const SizedBox(height: 16),

                // Tres pilares
                _buildWarrantyPillar('Derrames de líquidos', 'assets/images/icon1.svg', theme),
                const SizedBox(height: 8),
                _buildWarrantyPillar('Sobretensiones eléctricas', 'assets/images/icon2.svg', theme),
                const SizedBox(height: 8),
                _buildWarrantyPillar('Caídas accidentales', 'assets/images/icon3.svg', theme),

                const SizedBox(height: 16),

                // Tres pasos de registro
                Row(
                  children: [
                    _buildWarrantyStep('1', 'Regístrese como miembro ASUS', theme),
                    const SizedBox(width: 8),
                    _buildWarrantyStep('2', 'Registre su producto en 90 días', theme),
                    const SizedBox(width: 8),
                    _buildWarrantyStep('3', '¡Disfrute de la tranquilidad!', theme),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // --- Columna Derecha: escudo grande ---
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/images/apw.svg',
                width: 90,
                colorFilter: ColorFilter.mode(theme.primary.withValues(alpha: 0.85), BlendMode.srcIn),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyStep(String number, String desc, RetailTheme theme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: theme.primary,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: Text(number,
                    style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: const TextStyle(color: Colors.white70, fontSize: 9, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarrantyPillar(String text, String iconPath, RetailTheme theme) {
    return Row(
      children: [
        SvgPicture.asset(
          iconPath,
          width: 22,
          colorFilter: ColorFilter.mode(theme.primary, BlendMode.srcIn),
        ),
        const SizedBox(width: 15),
        Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }


  Widget _buildRetailCardIcon(RetailStore store) {
    switch (store) {
      case RetailStore.falabella:
        return SvgPicture.asset('assets/images/store-falabella.svg', height: 24, semanticsLabel: 'Card Icon');
      case RetailStore.paris:
        return Image.asset('assets/images/store-paris.png', height: 24, fit: BoxFit.contain);
      case RetailStore.ripley:
        return SvgPicture.asset('assets/images/store-ripley.svg', height: 24, semanticsLabel: 'Card Icon');
      case RetailStore.none:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFloatingReturnWindow(SpecsProvider provider) {
    final theme = RetailTheme.of(provider.store);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primary.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icono + etiqueta de modo prueba
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.science_outlined, color: theme.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'MODO PRUEBA',
                  style: GoogleFonts.outfit(
                    color: theme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'El PC se restaurará automáticamente si queda inactivo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 9, height: 1.4),
            ),
            const SizedBox(height: 20),

            // Botón principal: VER DETALLES
            ElevatedButton(
              onPressed: () {
                // Restaurar ventana completa + abrir specs
                provider.restoreKiosk();
                _resumeVideos();
                Future.delayed(const Duration(milliseconds: 400), _showSpecsDetail);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                'VER DETALLES',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
