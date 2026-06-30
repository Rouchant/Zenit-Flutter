import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/specs_provider.dart';
import 'screens/kiosk_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Inicializar MediaKit para decodificación de video nativa de alto rendimiento
  MediaKit.ensureInitialized();

  // 2. Inicializar el manejador de ventanas de escritorio
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    
    // Configurar ventana principal oculta inicialmente para evitar parpadeos
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // Sin barra de título de Windows
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      // Configurar modo kiosk de pantalla completa por defecto
      await windowManager.setFullScreen(true);
      await windowManager.setAlwaysOnTop(true);
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SpecsProvider()..loadSpecs()),
      ],
      child: const ZenitKioskApp(),
    ),
  );
}

class ZenitKioskApp extends StatelessWidget {
  const ZenitKioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SpecsProvider>(
      builder: (context, provider, child) {
        // Enlazar tema del retail seleccionado
        final retailTheme = RetailTheme.of(provider.store);

        return MaterialApp(
          title: 'Zenit Showcase',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            // Cargar los colores primario y secundario basados en el retail activo
            colorScheme: ColorScheme.dark(
              primary: retailTheme.primary,
              secondary: retailTheme.secondary,
              surface: const Color(0xFF111111),
            ),
            fontFamily: 'Outfit', // Usaremos Google Fonts Outfit en la UI
          ),
          home: const KioskScreen(),
        );
      },
    );
  }
}
