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
    if (ke.key != 'Enter' && ke.code != 'Enter' && ke.code != 'NumpadEnter') {
      return;
    }
    if (ke.shiftKey) return;
    if (ke.isComposing) return;
    if (!_isComposerTarget(ke.target)) return;
    ke.preventDefault();
    ke.stopPropagation();
    onSend();
  }).toJS;
  web.document.addEventListener('keydown', _onKeyDown!, true.toJS);
}

bool _isComposerTarget(web.EventTarget? target) {
  web.Element? el;
  try {
    el = target as web.Element;
  } catch (_) {
    return false;
  }
  web.Element? node = el;
  while (node != null) {
    final tag = node.tagName.toLowerCase();
    if (tag == 'textarea' || tag == 'input') return true;
    if (node.getAttribute('contenteditable') == 'true') return true;
    final cls = (node.getAttribute('class') ?? '').toLowerCase();
    if (cls.contains('flt-text-editing')) return true;
    node = node.parentElement;
  }
  return false;
}

void unregisterWebComposerEnterToSend() {
  if (_onKeyDown == null) return;
  web.document.removeEventListener('keydown', _onKeyDown!, true.toJS);
  _onKeyDown = null;
}
