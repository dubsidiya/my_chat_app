import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class WebDroppedFile {
  final String name;
  final Uint8List bytes;

  const WebDroppedFile({required this.name, required this.bytes});
}

JSFunction? _onDragOver;
JSFunction? _onDrop;

/// Обход багов desktop_drop в Chrome/Edge на Windows:
/// `webkitGetAsEntry()` часто null для файлов с рабочего стола, а DropDone
/// ещё и отбрасывается, если координаты не попали в виджет.
void registerWebFileDrop(void Function(List<WebDroppedFile> files) onDrop) {
  unregisterWebFileDrop();

  _onDragOver = ((web.Event event) {
    event.preventDefault();
  }).toJS;

  _onDrop = ((web.Event event) {
    event.preventDefault();
    event.stopPropagation();
    final dragEvent = event as web.DragEvent;
    final list = dragEvent.dataTransfer?.files;
    if (list == null || list.length == 0) return;
    final captured = <web.File>[];
    for (var i = 0; i < list.length; i++) {
      final file = list.item(i);
      if (file != null) captured.add(file);
    }
    if (captured.isEmpty) return;
    unawaited(_readFiles(captured, onDrop));
  }).toJS;

  web.document.addEventListener('dragover', _onDragOver!);
  web.document.addEventListener('drop', _onDrop!);
}

Future<void> _readFiles(
  List<web.File> files,
  void Function(List<WebDroppedFile> files) onDrop,
) async {
  final out = <WebDroppedFile>[];
  for (final file in files) {
    try {
      final buffer = await file.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      if (bytes.isEmpty) continue;
      out.add(WebDroppedFile(name: file.name, bytes: bytes));
    } catch (_) {}
  }
  if (out.isNotEmpty) onDrop(out);
}

void unregisterWebFileDrop() {
  if (_onDragOver != null) {
    web.document.removeEventListener('dragover', _onDragOver!);
    _onDragOver = null;
  }
  if (_onDrop != null) {
    web.document.removeEventListener('drop', _onDrop!);
    _onDrop = null;
  }
}
