import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class VideoMeta {
  final String path;
  final String name;

  VideoMeta({required this.path, required this.name});

  Map<String, dynamic> toJson() => {'path': path, 'name': name};

  factory VideoMeta.fromJson(Map<String, dynamic> json) {
    return VideoMeta(
      path: json['path'] ?? '',
      name: json['name'] ?? '',
    );
  }
}

class VaultService {
  late final Directory appDataDir;
  late final Directory customVideosDir;
  late final File storeFile;

  void initialize() {
    // Buscar la ruta de AppData\Local\com.zenit.app para compatibilidad con Tauri
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    if (localAppData.isNotEmpty) {
      appDataDir = Directory(p.join(localAppData, 'com.zenit.app'));
    } else {
      // Fallback si no se encuentra (entornos no-Windows o pruebas)
      appDataDir = Directory(p.join(Directory.systemTemp.path, 'com.zenit.app'));
    }

    customVideosDir = Directory(p.join(appDataDir.path, 'custom-videos'));
    storeFile = File(p.join(appDataDir.path, 'store.json'));

    // Asegurar que existan los directorios
    if (!appDataDir.existsSync()) {
      appDataDir.createSync(recursive: true);
    }
    if (!customVideosDir.existsSync()) {
      customVideosDir.createSync(recursive: true);
    }
  }

  // --- PERSISTENCIA CONFIG COMPATIBLE ---

  Future<Map<String, dynamic>> loadSpecsFromStore() async {
    try {
      if (await storeFile.exists()) {
        final content = await storeFile.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> root = jsonDecode(content);
          // En tauri-plugin-store los valores se guardan bajo llaves raíz
          if (root.containsKey('specs')) {
            return root['specs'] as Map<String, dynamic>;
          }
        }
      }
    } catch (e) {
      debugPrint('[VaultService] Error al cargar store.json: $e');
    }
    return {};
  }

  Future<void> saveSpecsToStore(Map<String, dynamic> specs) async {
    try {
      Map<String, dynamic> root = {};
      if (await storeFile.exists()) {
        final content = await storeFile.readAsString();
        if (content.isNotEmpty) {
          try {
            root = jsonDecode(content);
          } catch (_) {}
        }
      }
      
      root['specs'] = specs;
      
      final encoder = const JsonEncoder.withIndent('  ');
      await storeFile.writeAsString(encoder.convert(root));
    } catch (e) {
      debugPrint('[VaultService] Error al guardar store.json: $e');
    }
  }

  // --- GESTIÓN DE VIDEOS DE LA BÓVEDA ---

  File get _metaFile => File(p.join(customVideosDir.path, 'meta.json'));

  Future<List<VideoMeta>> loadVideoMeta() async {
    try {
      if (await _metaFile.exists()) {
        final content = await _metaFile.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> rawList = jsonDecode(content);
          return rawList.map((e) => VideoMeta.fromJson(e)).toList();
        }
      }
    } catch (e) {
      debugPrint('[VaultService] Error al cargar meta.json: $e');
    }
    return [];
  }

  Future<void> _saveVideoMeta(List<VideoMeta> meta) async {
    try {
      final encoder = const JsonEncoder.withIndent('  ');
      await _metaFile.writeAsString(encoder.convert(meta.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('[VaultService] Error al guardar meta.json: $e');
    }
  }

  Future<List<VideoMeta>> listCustomVideos() async {
    final List<VideoMeta> videos = [];
    final List<VideoMeta> meta = await loadVideoMeta();

    if (await customVideosDir.exists()) {
      final entities = customVideosDir.listSync();
      for (var entity in entities) {
        if (entity is File && p.basename(entity.path) != 'meta.json') {
          final path = entity.path;
          // Buscar el nombre en meta.json, de lo contrario usar el nombre del archivo sin extensión
          final matched = meta.firstWhere((element) => element.path == path, 
              orElse: () => VideoMeta(path: path, name: p.basenameWithoutExtension(path)));
          videos.add(matched);
        }
      }
    }
    return videos;
  }

  // Copia un archivo MP4 externo a la bóveda local sanitizando el nombre
  Future<String?> saveCustomVideo(String sourcePath, [String? customName]) async {
    final src = File(sourcePath);
    if (!await src.exists()) return null;

    final stat = await src.stat();
    final fileSize = stat.size;

    // 1. Detección de Duplicados (Mismo tamaño y nombre base aproximado)
    final metaList = await loadVideoMeta();
    final originalName = p.basename(sourcePath);
    for (var entry in metaList) {
      final entryFile = File(entry.path);
      if (await entryFile.exists()) {
        final entryStat = await entryFile.stat();
        if (entryStat.size == fileSize && p.basename(entry.path).contains(p.basenameWithoutExtension(originalName))) {
          return entry.path;
        }
      }
    }

    // 2. Validar límite de capacidad (Máximo 5 videos activos)
    final activeCount = metaList.where((element) => File(element.path).existsSync()).length;
    if (activeCount >= 5) {
      throw 'La bóveda está llena (máximo 5 videos). Elimina uno para continuar.';
    }

    // 3. Validar tamaño (Máximo 50MB)
    if (fileSize > 52428800) {
      throw 'El video supera el límite de 50MB permitido.';
    }

    // 4. Validar caracteres alfanuméricos si se especifica
    if (customName != null && customName.isNotEmpty) {
      final reg = RegExp(r'^[a-zA-Z0-9 _\-]+$');
      if (!reg.hasMatch(customName)) {
        throw 'El nombre solo puede contener letras, números, espacios, guiones o guiones bajos.';
      }
    }

    final ext = p.extension(sourcePath).replaceAll('.', '');
    final cleanName = customName ?? p.basenameWithoutExtension(sourcePath);
    
    // Formatear nombre de archivo con timestamp aleatorio para evitar colisiones
    final randId = DateTime.now().millisecondsSinceEpoch % 10000;
    final safeFileName = cleanName.replaceAll(RegExp(r'[^a-zA-Z0-9 _\-]'), '_');
    final newFileName = '${safeFileName}_$randId.$ext';
    final destPath = p.join(customVideosDir.path, newFileName);

    // 5. Copiar el archivo
    await src.copy(destPath);

    // 6. Guardar en meta.json
    metaList.add(VideoMeta(path: destPath, name: cleanName));
    await _saveVideoMeta(metaList);

    return destPath;
  }

  // Elimina físicamente un video y limpia referencias
  Future<void> deleteCustomVideo(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }

    // Limpiar de meta.json
    final metaList = await loadVideoMeta();
    metaList.removeWhere((element) => element.path == path);
    await _saveVideoMeta(metaList);
  }

  // Limpia archivos huérfanos que estén en la carpeta pero no registrados en meta.json
  Future<void> cleanupOrphanVideos() async {
    try {
      final metaList = await loadVideoMeta();
      final registeredPaths = metaList.map((e) => e.path).toSet();

      if (await customVideosDir.exists()) {
        final entities = customVideosDir.listSync();
        for (var entity in entities) {
          if (entity is File && p.basename(entity.path) != 'meta.json') {
            if (!registeredPaths.contains(entity.path)) {
              await entity.delete();
              debugPrint('[VaultService] Archivo huérfano eliminado: ${entity.path}');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[VaultService] Error al limpiar archivos huérfanos: $e');
    }
  }
}
