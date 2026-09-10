import 'package:flutter/material.dart';

/// Заглушка: на mobile/desktop используется обычный [TextField].
class WebChatComposer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: const InputDecoration(
        hintText: 'Сообщение',
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      maxLines: 6,
      minLines: 1,
      textCapitalization: TextCapitalization.sentences,
      onChanged: onChanged,
    );
  }
}
