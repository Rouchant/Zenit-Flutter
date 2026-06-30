import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

class WindowService {
  Timer? _idleTimer;
  Timer? _focusWatchdogTimer;
  bool _enforceAlwaysOnTop = true;
  bool _isFloatingMode = false;
  bool get isFloatingMode => _isFloatingMode;

  // Callback to trigger screensaver when OS idle limit is reached
  Function? onIdleTrigger;
  // Callback when activity is detected in screensaver
  Function? onActivityDetected;

  void initialize() {
    if (Platform.isWindows) {
      preventSleep();
      runPowercfgSetup();
      _startFocusWatchdog();
    }
  }

  void preventSleep() {
    if (!Platform.isWindows) return;
    // Evitar suspensión de pantalla y sistema de forma nativa e ininterrumpida
    SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED);
  }

  Future<void> runPowercfgSetup() async {
    if (!Platform.isWindows) return;
    try {
      // 1. Obtener los esquemas de energía disponibles
      final result = await Process.run('powercfg', ['/l']);
      final guids = <String>[];
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (var line in lines) {
          if (line.contains('GUID')) {
            final parts = line.split(' ');
            for (var part in parts) {
              if (part.length == 36 && part.contains('-')) {
                guids.add(part.trim());
              }
            }
          }
        }
      }
      
      if (guids.isEmpty) {
        guids.add('SCHEME_CURRENT');
      }

      // 2. Desactivar suspensión en batería y corriente
      for (var guid in guids) {
        for (var pair in [
          ['SUB_SLEEP', 'HIBERNATEIDLE', '0'],
          ['SUB_SLEEP', 'STANDBYIDLE', '0'],
          ['SUB_VIDEO', 'VIDEOIDLE', '0'],
        ]) {
          await Process.run('powercfg', ['/setacvalueindex', guid, pair[0], pair[1], pair[2]]);
          await Process.run('powercfg', ['/setdcvalueindex', guid, pair[0], pair[1], pair[2]]);
        }
      }

      // 3. Aplicar plan y desactivar hibernación
      await Process.run('powercfg', ['/s', 'SCHEME_CURRENT']);
      await Process.run('powercfg', ['/hibernate', 'off']);
      debugPrint('[WindowService] Configuración de powercfg aplicada correctamente.');
    } catch (e) {
      debugPrint('[WindowService] Error en powercfg: $e');
    }
  }

  // Calcula el tiempo de inactividad de Windows (en milisegundos)
  int getSystemIdleTime() {
    if (!Platform.isWindows) return 0;
    
    final lii = calloc<LASTINPUTINFO>();
    lii.ref.cbSize = sizeOf<LASTINPUTINFO>();
    
    if (GetLastInputInfo(lii) != 0) {
      final lastInput = lii.ref.dwTime;
      final current = GetTickCount();
      calloc.free(lii);
      
      if (lastInput < current) {
        return current - lastInput;
      }
      return current;
    }
    
    calloc.free(lii);
    return 0;
  }

  // Activa el monitoreo de inactividad de Windows cuando la app está minimizada (flotando)
  void startSystemIdleMonitor({
    required int idleLimitMs,
    required Function onIdleTriggered,
    required Function onActivity,
  }) {
    onIdleTrigger = onIdleTriggered;
    onActivityDetected = onActivity;

    _idleTimer?.cancel();
    
    final startTime = DateTime.now();
    const pollInterval = Duration(seconds: 2);
    const activityThresholdMs = 3000;
    bool isRestored = false;

    _idleTimer = Timer.periodic(pollInterval, (timer) {
      final idleTime = getSystemIdleTime();
      final elapsedSinceStart = DateTime.now().difference(startTime).inMilliseconds;
      
      // El tiempo de inactividad real es el mínimo entre la inactividad del sistema y el tiempo transcurrido desde que empezamos
      final effectiveIdleTime = idleTime < elapsedSinceStart ? idleTime : elapsedSinceStart;
      
      // Si la inactividad supera el límite, restaurar Zenit
      if (!isRestored && effectiveIdleTime >= idleLimitMs) {
        isRestored = true;
        onIdleTrigger?.call();
        restoreKioskMode();
        // Esperar un momento a que se estabilice el foco
        Future.delayed(const Duration(seconds: 6), () {
          isRestored = false;
        });
      }
      
      // Si ya está restaurado pero detectamos actividad real del usuario
      if (isRestored && idleTime < activityThresholdMs) {
        onActivityDetected?.call();
        timer.cancel();
      }
    });
  }

  void stopSystemIdleMonitor() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  // Watchdog periódico de foco
  void _startFocusWatchdog() {
    _focusWatchdogTimer?.cancel();
    _focusWatchdogTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_enforceAlwaysOnTop || _isFloatingMode || !Platform.isWindows) return;
      
      final isFocused = await windowManager.isFocused();
      if (!isFocused) {
        // Forzar ventana al frente agresivamente
        await windowManager.focus();
        await windowManager.setAlwaysOnTop(true);
      }
    });
  }

  // Transicionar al modo flotante de retorno (simula minimizado con ventana pequeña en la esquina)
  Future<void> enterFloatingMode() async {
    _isFloatingMode = true;
    _enforceAlwaysOnTop = false;

    // 1. Remover pantalla completa y frame de ventana
    await windowManager.setFullScreen(false);
    await windowManager.setHasShadow(false);
    await windowManager.setResizable(false);
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(const ui.Color(0x00000000));
    
    // 2. Redimensionar a una ventana pequeña (240x200 lógicos)
    const double width = 240.0;
    const double height = 200.0;
    await windowManager.setSize(ui.Size(width, height));
    
    // 3. Posicionar en la esquina superior derecha de la pantalla principal
    // Buscaremos posicionar relativo a la pantalla principal
    // (Aproximación por fallback a 1920x1080 si hay problemas de lectura)
    double targetX = 1920.0 - width - 20.0;
    double targetY = 100.0;
    
    // Obtener dimensiones reales de pantalla
    try {
      // Usar Win32 directo para obtener la resolución del monitor principal
      final screenWidth = GetSystemMetrics(SM_CXSCREEN);
      final screenHeight = GetSystemMetrics(SM_CYSCREEN);
      if (screenWidth > 0) {
        targetX = screenWidth - width - 20.0;
        targetY = (screenHeight - height) / 2.0 - 30.0;
      }
    } catch (_) {}

    await windowManager.setPosition(ui.Offset(targetX, targetY));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.focus();
  }

  // Restaurar al modo kiosko de pantalla completa
  Future<void> restoreKioskMode() async {
    _isFloatingMode = false;
    _enforceAlwaysOnTop = true;

    // 1. Ocultar bordes y forzar pantalla completa
    await windowManager.setFullScreen(true);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setResizable(true);
    
    // 2. Simular ESCAPE para quitar del foco menús del sistema (Inicio, etc)
    simulateEscapeKey();

    // 3. Tomar foco absoluto
    await windowManager.focus();
  }

  void simulateEscapeKey() {
    if (!Platform.isWindows) return;
    
    final input = calloc<INPUT>();
    input.ref.type = INPUT_KEYBOARD;
    input.ref.ki.wVk = VK_ESCAPE;
    input.ref.ki.dwFlags = 0; // Key down
    SendInput(1, input, sizeOf<INPUT>());

    input.ref.ki.dwFlags = KEYEVENTF_KEYUP; // Key up
    SendInput(1, input, sizeOf<INPUT>());
    
    calloc.free(input);
  }

  void setAlwaysOnTop(bool onTop) {
    _enforceAlwaysOnTop = onTop;
    windowManager.setAlwaysOnTop(onTop);
  }

  void closeApp() {
    exit(0);
  }

  void dispose() {
    _idleTimer?.cancel();
    _focusWatchdogTimer?.cancel();
  }
}
