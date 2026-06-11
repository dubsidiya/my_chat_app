import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Заголовок даты в списке сообщений чата («Сегодня», «Вчера», «15 февраля»).
class ChatDateHeader extends StatelessWidget {
  final String label;
  final Color? accentColor;

  const ChatDateHeader({
    super.key,
    required this.label,
    this.accentColor,
  });

  static Color get _defaultAccent => AppColors.primaryGlow;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? _defaultAccent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 12,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: color.withValues(alpha: 0.95),
            ),
          ),
        ),
      ),
    );
  }
}
