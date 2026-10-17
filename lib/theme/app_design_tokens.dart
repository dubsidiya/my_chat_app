import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Профессиональные дизайн-токены для премиум UI
/// 
/// Следует паттернам из flutter-taste-skill:
/// - Glassmorphism с inner borders
/// - Mesh gradients для organic backgrounds
/// - Neon glows вместо flat shadows
/// - Bento grid patterns
class AppDesignTokens {
  AppDesignTokens._();

  /// Glassmorphism эффект для карточек
  static BoxDecoration glassCard(ColorScheme scheme, {
    double alpha = 0.1,
    double borderAlpha = 0.1,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: alpha),
          Colors.white.withValues(alpha: alpha * 0.6),
        ],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        // Критичный inner border для glassmorphism
        color: Colors.white.withValues(alpha: borderAlpha),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.08),
          blurRadius: 24,
          spreadRadius: -4,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Mesh gradient background (organic, multi-radial)
  static BoxDecoration meshGradientBackground() {
    return BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.topLeft,
        radius: 1.2,
        colors: [
          AppColors.primary.withValues(alpha: 0.15),
          AppColors.backgroundDark,
        ],
      ),
    );
  }

  /// Neon glow для premium elements
  static List<BoxShadow> neonGlow({
    Color? color,
    double intensity = 1.0,
  }) {
    final glowColor = color ?? AppColors.primaryGlow;
    return [
      BoxShadow(
        color: glowColor.withValues(alpha: 0.4 * intensity),
        blurRadius: 16 * intensity,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: glowColor.withValues(alpha: 0.2 * intensity),
        blurRadius: 32 * intensity,
        spreadRadius: -4,
        offset: Offset(0, 4 * intensity),
      ),
    ];
  }

  /// Compound shadow (ambient + directional)
  static List<BoxShadow> compoundShadow(ColorScheme scheme) {
    final isLight = AppColors.isLight;
    return [
      // Ambient shadow
      BoxShadow(
        color: (isLight ? Colors.black : AppColors.primary)
            .withValues(alpha: isLight ? 0.04 : 0.12),
        blurRadius: 8,
        spreadRadius: 0,
      ),
      // Directional shadow
      BoxShadow(
        color: (isLight ? Colors.black : AppColors.primaryGlow)
            .withValues(alpha: isLight ? 0.08 : 0.18),
        blurRadius: 16,
        spreadRadius: -2,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// Staggered animation delay для entrance
  static Duration staggerDelay(int index) {
    return Duration(milliseconds: 50 * index);
  }

  /// Mesh gradient overlay для backgrounds
  static BoxDecoration meshOverlay() {
    return BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.topRight,
        radius: 1.5,
        colors: [
          AppColors.cyberAccent.withValues(alpha: 0.08),
          Colors.transparent,
          AppColors.primary.withValues(alpha: 0.06),
        ],
        stops: const [0.0, 0.5, 1.0],
      ),
    );
  }
}
