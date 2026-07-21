import 'dart:typed_data';

/// Returns `true` if saved, `false` if cancelled.
Future<bool> saveDownloadFileBytes({
  required String filename,
  required Uint8List bytes,
  List<String>? allowedExtensions,
}) async {
  throw UnsupportedError('saveDownloadFile недоступен на этой платформе');
}
