import 'dart:typed_data';

class WebDroppedFile {
  final String name;
  final Uint8List bytes;

  const WebDroppedFile({required this.name, required this.bytes});
}

void registerWebFileDrop(void Function(List<WebDroppedFile> files) onDrop) {}

void unregisterWebFileDrop() {}
