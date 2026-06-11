import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'glow_empty_state.dart';

/// Заглушка «Нет сообщений» в пустом чате.
class ChatEmptyMessages extends StatelessWidget {
  final Color? accentColor;

  const ChatEmptyMessages({super.key, this.accentColor});

  static Color get _defaultAccent => AppColors.primaryGlow;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? _defaultAccent;
    return Center(
      child: GlowEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Нет сообщений',
        subtitle: 'Напишите первое сообщение',
        accentColor: color,
      ),
    );
  }
}
