import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Returns `true` if saved, `false` if cancelled.
Future<bool> saveDownloadFileBytes({
  required String filename,
  required Uint8List bytes,
  List<String>? allowedExtensions,
}) async {
  final ext = allowedExtensions ?? _extensionsFromFilename(filename);

  // Mobile: bytes обязательны — плагин сам пишет через SAF / UIDocumentPicker.
  if (Platform.isAndroid || Platform.isIOS) {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить файл',
      fileName: filename,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ext,
    );
    return path != null && path.isNotEmpty;
  }

  // Desktop (в т.ч. macOS): bytes передавать нельзя — на macOS это UnsupportedError.
  // Диалог только выбирает путь; содержимое пишем сами.
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Сохранить файл',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: ext,
  );
  if (path == null || path.isEmpty) {
    return false;
  }
  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}

List<String> _extensionsFromFilename(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return ['bin'];
  return [filename.substring(dot + 1).toLowerCase()];
}
