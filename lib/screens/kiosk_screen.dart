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
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    theme.primary.withValues(alpha: 0.45),
                    BlendMode.srcATop,
                  ),
                  child: Image.asset(
                    provider.isAsus ? 'assets/images/background-asus.png' : 'assets/images/background-generic.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // Video Loop de Fondo
              if (_playersInitialized)
                SizedBox.expand(
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      theme.primary.withValues(alpha: 0.55),
                      BlendMode.srcATop,
                    ),
                    child: Video(
                      controller: _bgController,
                      fit: BoxFit.cover,
                      controls: NoVideoControls,
                    ),
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
                        theme.gradientStart.withValues(alpha: 0.2),
                        theme.gradientEnd.withValues(alpha: 0.5),
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
                              // CrossAxisAlignment.center: alinear video y especificaciones al centro vertical
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Izquierda: ~35% del ancho total → flex 7
                                Expanded(
                                  flex: 7,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildSpecsGrid(provider, theme),
                                      const SizedBox(height: 24),
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildLandingVideoBox(provider, theme),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Izquierda: Botón Garantía Perfecta (solo ASUS con opción activa)
                                          if (provider.isAsus && provider.currentSpecs['showAsusWarrantyTicker'] == true)
                                            SizedBox(
                                              width: 260,
                                              child: _buildWarrantyTriggerButton(theme),
                                            ),
                                          // Derecha: Precios
                                          _buildSeparatePricesContainer(provider, theme),
                                        ],
                                      ),
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
    
    // Formatear Marca + Modelo para el badge
    final String brandRaw = (provider.currentSpecs['brand'] ?? '').toString();
    final String modelRaw = (provider.currentSpecs['model'] ?? '').toString();
    String brandFormatted = brandRaw;
    if (brandRaw.toLowerCase() == 'asus') {
      brandFormatted = 'Asus';
    } else if (brandRaw.isNotEmpty) {
      brandFormatted = brandRaw[0].toUpperCase() + brandRaw.substring(1);
    }
    final String badgeText = '${brandFormatted} ${modelRaw}'.trim();
    final String textToDisplay = badgeText.isNotEmpty ? badgeText : provider.store.name.toUpperCase();

    Widget brandLogo;
    if (brand.contains('asus')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-asus.svg',
        height: 60,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('hp') || brand.contains('hewlett')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-hp.svg',
        height: 60,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('lenovo')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-lenovo.svg',
        height: 60,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('acer')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-acer.svg',
        height: 60,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('samsung')) {
      brandLogo = SvgPicture.asset(
        'assets/images/brand-samsung.svg',
        height: 60,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    } else if (brand.contains('dell')) {
      brandLogo = Text('DELL',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 2));
    } else if (brand.contains('microsoft')) {
      brandLogo = Text('SURFACE',
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: 1.5));
    } else {
      brandLogo = Text(
        brand.isNotEmpty ? brand.toUpperCase() : 'ZENIT',
        style: GoogleFonts.outfit(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: 2),
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
              if (theme.logoAsset != null || theme.logoPngAsset != null) ...[
                const SizedBox(width: 16),
                Container(
                  width: 1.5,
                  height: 48,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 16),
                theme.storeLogoWidget,
              ],
            ],
          ),
        ),

        // Badge de Marca + Modelo a la derecha (solo si hay tienda)
        if (theme.logoAsset != null || theme.logoPngAsset != null)
          Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(31),
            ),
            child: Text(
              textToDisplay,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
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
    final ramType = specs['ramType'] ?? '';
    final cpuGen = specs['gen'] ?? '';
    final int cores = specs['cores'] ?? 0;
    final int threads = specs['threads'] ?? 0;
    final String cpuSubtitle = (cores > 0 && threads > 0) ? '$cores núcleos / $threads hilos' : '';

    // Determinar icono de procesador (a la izquierda)
    String cpuIcon = 'assets/images/ui-cpu.svg';
    final cpuVendor = _detectChipVendor(processor);
    if (cpuVendor == 'intel') {
      cpuIcon = 'assets/images/brand-intel.svg';
    } else if (cpuVendor == 'amd') {
      cpuIcon = 'assets/images/brand-amd.svg';
    } else if (cpuVendor == 'snapdragon') {
      cpuIcon = 'assets/images/brand-snapdragon.svg';
    }

    // Determinar icono de GPU (a la izquierda)
    String gpuIcon = 'assets/images/ui-gpu.svg';
    final gpuVendor = _detectChipVendor(gpu);
    if (gpuVendor == 'nvidia') {
      gpuIcon = 'assets/images/brand-nvidia.svg';
    }

    final cards = [
      _buildSpecCard(
        'PROCESADOR', 
        processor, 
        cpuIcon, 
        theme: theme,
        subtitle: cpuSubtitle.isNotEmpty ? cpuSubtitle : null,
        suffix: cpuGen.toString().isNotEmpty && cpuGen.toString() != 'Desconocida'
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cpuGen.toString(),
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
      _buildSpecCard(
        'MEMORIA RAM', 
        specs['ram'] ?? 'Cargando...', 
        'assets/images/ui-ram.svg', 
        theme: theme,
        suffix: ramType.toString().isNotEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ramType.toString(),
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
      _buildSpecCard('ALMACENAMIENTO', specs['storage'] ?? 'Cargando...', 'assets/images/ui-storage.svg', theme: theme),
      _buildSpecCard('PANTALLA', specs['display'] ?? 'Cargando...', 'assets/images/ui-display.svg', theme: theme),
      _buildSpecCard('GRÁFICOS', gpu, gpuIcon, theme: theme),
      _buildSpecCard('SISTEMA OPERATIVO', specs['os'] ?? 'Cargando...', 'assets/images/ui-windows.svg', theme: theme),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: cards.map((c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: c,
      )).toList(),
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

  Widget _buildSpecCard(
    String label, 
    String value, 
    String iconAsset, {
    required RetailTheme theme,
    Widget? suffix,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
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
          SizedBox(
            width: 76,
            height: 76,
            child: Center(
              child: SvgPicture.asset(
                iconAsset,
                width: iconAsset.contains('brand-amd') ? 48 : 60,
                height: iconAsset.contains('brand-amd') ? 48 : 60,
                colorFilter: iconAsset.contains('brand-') 
                    ? null 
                    : const ColorFilter.mode(Colors.black, BlendMode.srcIn),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Etiqueta + Valor
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF888888),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (suffix != null) ...[
                      const SizedBox(width: 8),
                      suffix,
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF555555),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCtaButton(SpecsProvider provider, RetailTheme theme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          // Minimizar al modo flotante de prueba para que el cliente use el PC
          _pauseVideos();
          provider.minimizeKioskWithOSWatchdog();
        },
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.8,
            child: Container(
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.primary, theme.primary.withValues(alpha: 0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
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
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
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
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
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
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeparatePricesContainer(SpecsProvider provider, RetailTheme theme) {
    final specs = provider.currentSpecs;
    final hasPrimary = (specs['pricePrimary'] ?? '').toString().isNotEmpty;
    final hasSecondary = (specs['priceSecondary'] ?? '').toString().isNotEmpty;
    if (!hasPrimary && !hasSecondary) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasPrimary) ...[
            // Línea de precio exclusivo tarjeta
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXCLUSIVO TARJETA',
                      style: GoogleFonts.outfit(
                        color: theme.primary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      specs['pricePrimary'],
                      style: GoogleFonts.outfit(
                        color: theme.primary,
                        fontSize: 41,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                _buildRetailCardIcon(provider.store),
              ],
            ),
          ],
          if (hasPrimary && hasSecondary) const SizedBox(height: 12),
          if (hasSecondary) ...[
            // Línea de precio todo medio de pago
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TODO MEDIO DE PAGO',
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  specs['priceSecondary'],
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWarrantyTriggerButton(RetailTheme theme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _showWarrantyOverlay = !_showWarrantyOverlay),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B29B5), Color(0xFF2764DE)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1B29B5).withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                'Ver Garantía Perfecta',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildASUSWarrantyCard(RetailTheme theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEBF4FF), Color(0xFFFFFFFF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Columna Izquierda: info ---
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Título y descripción
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Garantía Perfecta ASUS',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF003B7A), // Azul corporativo de ASUS
                        fontSize: 46,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '¡Registre sus productos* para recibir una Garantía Perfecta ASUS por 1 año!',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF1E293B),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ASUS ofrece un año de Garantía Perfecta ASUS (protección complementaria contra daños accidentales) en ciertos productos para que cuando ocurran accidentes, lo tengamos cubierto. Complete el registro del producto dentro de los primeros 90 días posteriores a la compra y disfrute de la tranquilidad con la Garantía Perfecta ASUS.',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF475569),
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                // Tres pilares en formato vertical sin tarjetas oscuras
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildWarrantyPillarCard('Derrames de líquidos', 'assets/images/icon1.svg', theme),
                    _buildWarrantyPillarCard('Sobretensiones eléctricas', 'assets/images/icon2.svg', theme),
                    _buildWarrantyPillarCard('Caídas accidentales', 'assets/images/icon3.svg', theme),
                  ],
                ),

                // Tres pasos de registro
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        '¿Cómo recibir la Garantía Perfecta ASUS?',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF003B7A),
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWarrantyStep('1', 'Regístrese como miembro de ASUS', theme),
                        _buildWarrantyStep('2', 'Registre sus productos dentro de un plazo de 90 días posteriores a la compra', theme),
                        _buildWarrantyStep('3', '¡Disfrute de la tranquilidad con la Garantía Perfecta ASUS!', theme),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 24),

          // --- Columna Derecha: escudo grande ---
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              SvgPicture.asset(
                'assets/images/apw.svg',
                width: 130,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyStep(String number, String desc, RetailTheme theme) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Cuadrado con gradiente azul para el número de paso
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF003B7A), Color(0xFF005DC2)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF003B7A).withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'PASO',
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  number,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: const Color(0xFF334155),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyPillarCard(String text, String iconPath, RetailTheme theme) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            iconPath,
            width: 58,
            height: 58,
            colorFilter: const ColorFilter.mode(Color(0xFF1E293B), BlendMode.srcIn),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: const Color(0xFF1E293B),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildRetailCardIcon(RetailStore store) {
    switch (store) {
      case RetailStore.falabella:
        return SvgPicture.asset('assets/images/T-FALABELLA.svg', height: 32, semanticsLabel: 'Card Icon');
      case RetailStore.paris:
        return SvgPicture.asset('assets/images/T-CENCOSUD.svg', height: 32, semanticsLabel: 'Card Icon');
      case RetailStore.ripley:
        return SvgPicture.asset('assets/images/T-RIPLEY.svg', height: 32, semanticsLabel: 'Card Icon');
      case RetailStore.none:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFloatingReturnWindow(SpecsProvider provider) {
    final theme = RetailTheme.of(provider.store);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            provider.restoreKiosk();
            _resumeVideos();
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.primary, theme.primary.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.fullscreen_exit, color: Colors.black, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'VER DETALLES',
                    style: GoogleFonts.outfit(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
