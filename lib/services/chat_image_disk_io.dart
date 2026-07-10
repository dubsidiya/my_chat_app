import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

const _dirName = 'chat_image_cache_v1';

Directory? _dir;

Future<Directory?> _cacheDir() async {
  if (_dir != null) return _dir;
  try {
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> readChatImageDisk(String fileName) async {
  try {
    final dir = await _cacheDir();
    if (dir == null) return null;
    final file = File('${dir.path}/$fileName');
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  }
}

Future<void> writeChatImageDisk(String fileName, Uint8List bytes) async {
  try {
    final dir = await _cacheDir();
    if (dir == null) return;
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: false);
  } catch (_) {
    // диск недоступен — остаёмся на RAM
  }
}

Future<void> clearChatImageDisk() async {
  try {
    final dir = await _cacheDir();
    _dir = null;
    if (dir != null && await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (_) {
    _dir = null;
  }
}
