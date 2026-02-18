/// Stub: на web чтение по path не поддерживается, используйте bytes из file_picker.
Future<List<int>> readFileBytesFromPath(String path) async {
  throw UnsupportedError('На этой платформе используйте file.bytes из file_picker');
}
