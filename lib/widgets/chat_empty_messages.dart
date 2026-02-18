import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Заглушка «Нет сообщений» в пустом чате.
class ChatEmptyMessages extends StatelessWidget {
  final Color? accentColor;

  const ChatEmptyMessages({super.key, this.accentColor});

  static const Color _defaultAccent = AppColors.primaryGlow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accentColor ?? _defaultAccent;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: color.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Нет сообщений',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Напишите первое сообщение',
            style: TextStyle(
              fontSize: 14,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
