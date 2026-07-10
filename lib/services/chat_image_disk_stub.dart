import 'dart:typed_data';

/// Заглушка диска (web / без IO): только no-op.
Future<Uint8List?> readChatImageDisk(String fileName) async => null;

Future<void> writeChatImageDisk(String fileName, Uint8List bytes) async {}

Future<void> clearChatImageDisk() async {}
