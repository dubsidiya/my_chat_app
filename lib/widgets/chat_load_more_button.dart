import 'package:flutter/material.dart';

/// Кнопка «Загрузить старые сообщения» в списке чата.
class ChatLoadMoreButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? accentColor;

  const ChatLoadMoreButton({
    super.key,
    required this.onPressed,
    this.accentColor,
  });

  static const Color _defaultAccent = Color(0xFF667eea);

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? _defaultAccent;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(Icons.arrow_upward, size: 18, color: color),
          label: const Text('Загрузить старые сообщения'),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.35), width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}
