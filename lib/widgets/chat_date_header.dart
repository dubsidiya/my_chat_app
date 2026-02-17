import 'package:flutter/material.dart';

/// Заголовок даты в списке сообщений чата («Сегодня», «Вчера», «15 февраля»).
class ChatDateHeader extends StatelessWidget {
  final String label;
  final Color? accentColor;

  const ChatDateHeader({
    super.key,
    required this.label,
    this.accentColor,
  });

  static const Color _defaultAccent = Color(0xFF667eea);

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? _defaultAccent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.95),
            ),
          ),
        ),
      ),
    );
  }
}
