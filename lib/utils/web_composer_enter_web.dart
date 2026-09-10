import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Flutter web (особенно Edge/Chrome на Windows) отдаёт Enter нативному
/// `<textarea>`: новая строка, Dart `Focus.onKeyEvent` часто не вызывается.
/// Слушаем keydown в capture-фазе и шлём сообщение сами.
JSFunction? _onKeyDown;

void registerWebComposerEnterToSend(void Function() onSend) {
  unregisterWebComposerEnterToSend();
  _onKeyDown = ((web.Event event) {
    final ke = event as web.KeyboardEvent;
    if (ke.key != 'Enter') return;
    if (ke.shiftKey) return;
    if (ke.isComposing) return;
    final target = ke.target;
    if (target == null) return;
    final el = target as web.Element;
    final tag = el.tagName.toLowerCase();
    if (tag != 'textarea' && tag != 'input') return;
    ke.preventDefault();
    ke.stopPropagation();
    onSend();
  }).toJS;
  web.document.addEventListener('keydown', _onKeyDown!, true.toJS);
}

void unregisterWebComposerEnterToSend() {
  if (_onKeyDown == null) return;
  web.document.removeEventListener('keydown', _onKeyDown!, true.toJS);
  _onKeyDown = null;
}
