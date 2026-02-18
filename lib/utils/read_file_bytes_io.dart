import 'dart:io';

Future<List<int>> readFileBytesFromPath(String path) => File(path).readAsBytes();
