import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../providers/specs_provider.dart';

class ScreensaverPlayer extends StatefulWidget {
  const ScreensaverPlayer({super.key});

  @override
  State<ScreensaverPlayer> createState() => _ScreensaverPlayerState();
}

class _ScreensaverPlayerState extends State<ScreensaverPlayer> {
  late final Player _player;
  late final VideoController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPlaylist();
    });
  }

  void _startPlaylist() {
    final provider = Provider.of<SpecsProvider>(context, listen: false);
    final videoPaths = provider.getActiveScreensaverPaths();
    
    if (videoPaths.isEmpty) return;

    final playlist = videoPaths.map((p) => Media(p)).toList();
    
    _player.open(Playlist(playlist));
    _player.setPlaylistMode(PlaylistMode.loop);
    
    setState(() {
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          // Detectar interacción para desactivar screensaver
          final provider = Provider.of<SpecsProvider>(context, listen: false);
          provider.isVideoMode = false;
        },
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // Reproductor a pantalla completa
            SizedBox.expand(
              child: Video(
                controller: _controller,
                fit: BoxFit.cover,
                controls: NoVideoControls, // Sin controles visibles
              ),
            ),
            
            // Ticker sutil de interacción al fondo para instruir al cliente
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'TOCA LA PANTALLA PARA VER LAS ESPECIFICACIONES',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
