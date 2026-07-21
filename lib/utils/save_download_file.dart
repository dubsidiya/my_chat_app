import 'dart:typed_data';

import 'save_download_file_stub.dart'
    if (dart.library.io) 'save_download_file_io.dart' as impl;

/// Результат сохранения файла через системный диалог.
enum SaveDownloadOutcome {
  /// Файл сохранён пользователем в выбранное место (Загрузки / Файлы и т.п.).
  saved,

  /// Пользователь закрыл диалог без сохранения.
  cancelled,
}

/// Сохраняет [bytes] через системный «Save as» / document picker.
///
/// На телефоне пользователь сам выбирает папку (в т.ч. «Загрузки»),
/// а не получает файл во внутренний sandbox приложения.
/// На web не используется — вызывайте [downloadBinaryFile] / [downloadTextFile].
Future<SaveDownloadOutcome> saveDownloadFile({
  required String filename,
  required Uint8List bytes,
  List<String>? allowedExtensions,
}) async {
  final saved = await impl.saveDownloadFileBytes(
    filename: filename,
    bytes: bytes,
    allowedExtensions: allowedExtensions,
  );
  return saved ? SaveDownloadOutcome.saved : SaveDownloadOutcome.cancelled;
}
