import 'package:flutter/material.dart';

/// Ультрафиолетовая готическая палитра.
class AppColors {
  AppColors._();

  // Тёмная тема (готика)
  static const Color backgroundDark = Color(0xFF0D0221);
  static const Color surfaceDark = Color(0xFF1a0a2e);
  static const Color cardDark = Color(0xFF1e1035);
  static const Color cardElevatedDark = Color(0xFF2d1b4e);
  static const Color borderDark = Color(0xFF3d2a6e);

  // Ультрафиолет — акценты
  static const Color primary = Color(0xFF9D4EDD);
  static const Color primaryGlow = Color(0xFFC77DFF);
  static const Color accent = Color(0xFFE0AAFF);
  static const Color primaryDeep = Color(0xFF7B2CBF);

  // Текст
  static const Color onSurfaceDark = Color(0xFFE8E0F0);
  static const Color onSurfaceVariantDark = Color(0xFF9D8FB5);

  /// Неоновое свечение для кнопок и карточек.
  static List<BoxShadow> get neonGlow => [
        BoxShadow(
          color: primaryGlow.withValues(alpha: 0.5),
          blurRadius: 12,
          spreadRadius: 0,
          offset: const Offset(0, 0),
        ),
        BoxShadow(
          color: primary.withValues(alpha: 0.35),
          blurRadius: 24,
          spreadRadius: -4,
          offset: const Offset(0, 4),
        ),
      ];

  /// Сильное неоновое свечение (FAB, главные CTA).
  static List<BoxShadow> get neonGlowStrong => [
        BoxShadow(
          color: primaryGlow.withValues(alpha: 0.6),
          blurRadius: 16,
          spreadRadius: 0,
          offset: const Offset(0, 0),
        ),
        BoxShadow(
          color: primary.withValues(alpha: 0.5),
          blurRadius: 32,
          spreadRadius: -2,
          offset: const Offset(0, 6),
        ),
      ];

  /// Лёгкое свечение для полей ввода в фокусе.
  static List<BoxShadow> get neonGlowSoft => [
        BoxShadow(
          color: primaryGlow.withValues(alpha: 0.25),
          blurRadius: 12,
          spreadRadius: 0,
          offset: Offset.zero,
        ),
      ];

  // Светлая тема (сумеречная готика)
  static const Color backgroundLight = Color(0xFF1a0a2e);
  static const Color surfaceLight = Color(0xFF251538);
  static const Color cardLight = Color(0xFF2d1b4e);
  static const Color borderLight = Color(0xFF4a3a6e);
  static const Color onSurfaceLight = Color(0xFFE8E0F0);
  static const Color onSurfaceVariantLight = Color(0xFFB8A8D0);
}
