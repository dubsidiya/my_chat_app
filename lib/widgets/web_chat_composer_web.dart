import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Нативное `<textarea>` вместо Flutter [TextField].
///
/// Flutter web рисует HTML-оверлей над полем; на Windows (масштаб 125–150%)
/// он перехватывает клики по «отправить» и съедает Enter. Нативный textarea
/// этого оверлея не создаёт — Enter и кнопка отправки работают как в обычном сайте.
class WebChatComposer extends StatefulWidget {
  /// Последний текст из нативного textarea. Flutter [TextEditingController]
  /// на web часто пустой, пока поле в фокусе — отправка тогда молча отваливается.
  static String pendingText = '';

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final Color textColor;
  final Color hintColor;

  const WebChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onChanged,
    required this.textColor,
    required this.hintColor,
  });

  @override
  State<WebChatComposer> createState() => _WebChatComposerState();
}

class _WebChatComposerState extends State<WebChatComposer> {
  web.HTMLTextAreaElement? _textarea;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFromController);
  }

  @override
  void didUpdateWidget(WebChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _syncFromController();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    super.dispose();
  }

  void _syncFromController() {
    final ta = _textarea;
    if (ta == null) return;
    final next = widget.controller.text;
    if (ta.value != next) ta.value = next;
  }

  void _syncToController(String value) {
    WebChatComposer.pendingText = value;
    if (widget.controller.text == value) return;
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged(value);
  }

  String _cssColor(Color c) {
    return 'rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},${c.a})';
  }

  void _onElementCreated(Object element) {
    final ta = element as web.HTMLTextAreaElement;
    _textarea = ta;
    ta.rows = 2;
    ta.placeholder = 'Сообщение';
    ta.value = widget.controller.text;
    ta.setAttribute('aria-label', 'Сообщение');
    ta.setAttribute('data-placeholder-color', _cssColor(widget.hintColor));
    ta.style
      ..width = '100%'
      ..height = '100%'
      ..boxSizing = 'border-box'
      ..border = 'none'
      ..outline = 'none'
      ..resize = 'none'
      ..backgroundColor = 'transparent'
      ..color = _cssColor(widget.textColor)
      ..fontSize = '15px'
      ..lineHeight = '20px'
      ..fontFamily = 'inherit'
      ..padding = '12px 16px';
    ta.addEventListener(
      'input',
      ((web.Event _) {
        _syncToController(ta.value);
      }).toJS,
    );
    ta.addEventListener(
      'keydown',
      ((web.Event event) {
        final ke = event as web.KeyboardEvent;
        final isEnter =
            ke.key == 'Enter' || ke.code == 'Enter' || ke.code == 'NumpadEnter';
        if (!isEnter || ke.shiftKey || ke.isComposing) return;
        ke.preventDefault();
        ke.stopPropagation();
        _syncToController(ta.value);
        widget.onSend();
      }).toJS,
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'textarea',
      onElementCreated: _onElementCreated,
    );
  }
}
