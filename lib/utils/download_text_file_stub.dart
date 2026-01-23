Future<bool> downloadTextFile({
  required String filename,
  required String content,
  String mimeType = 'text/plain; charset=utf-8',
}) async {
  // Not supported on non-web platforms via this helper.
  return false;
}

