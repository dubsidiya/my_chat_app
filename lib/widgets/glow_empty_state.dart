import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'fade_scale_in.dart';

/// Пустое состояние с фирменным «гало»: иконка в градиентном круге
/// с мягким неоновым свечением, заголовок и подзаголовок.
/// Используется для «Нет сообщений», «Нет чатов» и подобных экранов.
class GlowEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? accentColor;

  const GlowEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = accentColor ?? AppColors.primaryGlow;
    return FadeScaleIn(
      duration: const Duration(milliseconds: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: AppColors.isLight ? 0.16 : 0.22),
                  AppColors.cyberAccent.withValues(alpha: 0.10),
                ],
              ),
              border: Border.all(
                color: accent.withValues(alpha: 0.32),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: AppColors.isLight ? 0.18 : 0.28),
                  blurRadius: 36,
                  spreadRadius: -6,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(icon, size: 42, color: accent),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: scheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
