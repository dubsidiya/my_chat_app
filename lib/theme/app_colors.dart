import 'package:flutter/material.dart';

import 'theme_variant.dart';

/// Внутренняя палитра — набор цветов конкретной темы.
///
/// Все экраны и виджеты обращаются к [AppColors], а тот делегирует значения
/// текущей активной палитре. Поэтому смена темы автоматически перекрашивает UI
/// без изменений в виджетах.
@immutable
class _AppPalette {
  final Brightness brightness;

  // Нейтральные поверхности
  final Color backgroundDark;
  final Color surfaceDark;
  final Color cardDark;
  final Color cardElevatedDark;
  final Color borderDark;

  // Акценты
  final Color primary;
  final Color primaryGlow;
  final Color accent;
  final Color primaryDeep;

  // Текст
  final Color onSurfaceDark;
  final Color onSurfaceVariantDark;

  // Состояния (ошибка/успех/предупреждение) — общие на тему
  final Color errorColor;
  final Color successColor;
  final Color warningColor;

  // Градиент фона списка чатов
  final LinearGradient homeBodyGradient;

  // Тени/свечения — рассчитываются на лету через геттеры,
  // поскольку зависят от primary/glow.
  const _AppPalette({
    required this.brightness,
    required this.backgroundDark,
    required this.surfaceDark,
    required this.cardDark,
    required this.cardElevatedDark,
    required this.borderDark,
    required this.primary,
    required this.primaryGlow,
    required this.accent,
    required this.primaryDeep,
    required this.onSurfaceDark,
    required this.onSurfaceVariantDark,
    required this.errorColor,
    required this.successColor,
    required this.warningColor,
    required this.homeBodyGradient,
  });
}

// ============================================================================
// Палитра 1: «Ультрафиолет» — тёмная готическая (исходный стиль приложения).
// ============================================================================
const _AppPalette _paletteUltravioletDark = _AppPalette(
  brightness: Brightness.dark,
  backgroundDark: Color(0xFF0D0221),
  surfaceDark: Color(0xFF1a0a2e),
  cardDark: Color(0xFF1e1035),
  cardElevatedDark: Color(0xFF2d1b4e),
  borderDark: Color(0xFF3d2a6e),
  primary: Color(0xFF9D4EDD),
  primaryGlow: Color(0xFFC77DFF),
  accent: Color(0xFFE0AAFF),
  primaryDeep: Color(0xFF7B2CBF),
  onSurfaceDark: Color(0xFFE8E0F0),
  onSurfaceVariantDark: Color(0xFF9D8FB5),
  errorColor: Color(0xFFE57373),
  successColor: Color(0xFF81C784),
  warningColor: Color(0xFFFFB74D),
  homeBodyGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.45, 1.0],
    colors: [
      Color(0xFF0D0221),
      Color(0xFF120A24),
      Color(0xFF1a0a2e),
    ],
  ),
);

// ============================================================================
// Палитра 2: «Аврора» — светлая премиальная с сиреневыми акцентами.
// Опирается на Material You (фиолетовая семья), чтобы сохранить узнаваемость
// бренда, но в светлом исполнении: мягкий лавандовый фон, чистый белый surface,
// насыщенный, но доступный для контраста primary.
// ============================================================================
const _AppPalette _paletteAuroraLight = _AppPalette(
  brightness: Brightness.light,
  // «Background» в светлой теме — это основной светлый фон страницы.
  backgroundDark: Color(0xFFFBFAFD),
  // «Surface» — карточки/панели по умолчанию.
  surfaceDark: Color(0xFFFFFFFF),
  // «Card» — мягкая лавандовая подложка для подсветки секций.
  cardDark: Color(0xFFF5F2FA),
  // «CardElevated» — лавандовая подложка для входящих пузырей и SnackBar:
  // должна заметно выделяться поверх белого surface.
  cardElevatedDark: Color(0xFFEDE7F8),
  // Border — деликатный, но различимый.
  borderDark: Color(0xFFE0DAEC),
  // Primary — насыщенный, читаемый на белом.
  primary: Color(0xFF7B4FCB),
  // Glow — чуть светлее primary, используется для подсветок и фокуса.
  primaryGlow: Color(0xFF9D6DE0),
  // Accent — мягкий лавандовый, для chip/pill/иконок 2-го уровня.
  accent: Color(0xFFB69DF8),
  // Deep — для градиентов «primary→primaryDeep».
  primaryDeep: Color(0xFF5A2EAA),
  // Текст: почти-чёрный с тёплым оттенком, чтобы не выглядел резко.
  onSurfaceDark: Color(0xFF1F1B2E),
  // Вторичный текст: чёткий, но мягкий.
  onSurfaceVariantDark: Color(0xFF615C70),
  // Состояния — насыщенные, чтобы выделялись на белом.
  errorColor: Color(0xFFD32F2F),
  successColor: Color(0xFF2E7D32),
  warningColor: Color(0xFFEF6C00),
  homeBodyGradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.55, 1.0],
    colors: [
      Color(0xFFFBFAFD),
      Color(0xFFF5F2FA),
      Color(0xFFEDE7F8),
    ],
  ),
);

/// Глобальные цвета приложения.
///
/// API намеренно сохранён неизменным после введения нескольких тем:
/// все обращения к [AppColors.primary] и т.п. остаются прежними, а под
/// капотом значения берутся из [AppColors.activeVariant].
///
/// Имена полей с суффиксом `Dark` исторически отражают исходную тёмную
/// палитру; в светлой теме они хранят соответствующие светлые значения.
class AppColors {
  AppColors._();

  static AppThemeVariant _activeVariant = AppThemeVariant.ultravioletDark;

  /// Текущая активная тема.
  static AppThemeVariant get activeVariant => _activeVariant;

  /// Меняет активную тему. Не вызывает rebuild — этим должен заняться
  /// слушатель ThemeController в `main.dart`.
  static void setActiveVariant(AppThemeVariant variant) {
    _activeVariant = variant;
  }

  static _AppPalette get _p {
    switch (_activeVariant) {
      case AppThemeVariant.ultravioletDark:
        return _paletteUltravioletDark;
      case AppThemeVariant.auroraLight:
        return _paletteAuroraLight;
    }
  }

  // --- Поверхности --------------------------------------------------------
  static Color get backgroundDark => _p.backgroundDark;
  static Color get surfaceDark => _p.surfaceDark;
  static Color get cardDark => _p.cardDark;
  static Color get cardElevatedDark => _p.cardElevatedDark;
  static Color get borderDark => _p.borderDark;

  // --- Акценты ------------------------------------------------------------
  static Color get primary => _p.primary;
  static Color get primaryGlow => _p.primaryGlow;
  static Color get accent => _p.accent;
  static Color get primaryDeep => _p.primaryDeep;

  // --- Текст --------------------------------------------------------------
  static Color get onSurfaceDark => _p.onSurfaceDark;
  static Color get onSurfaceVariantDark => _p.onSurfaceVariantDark;

  // --- Цвета состояний ----------------------------------------------------
  static Color get errorDark => _p.errorColor;
  static Color get successDark => _p.successColor;
  static Color get warningDark => _p.warningColor;

  /// Является ли активная тема светлой.
  static bool get isLight => _p.brightness == Brightness.light;

  /// Тени/свечения. В светлой теме делаем их мягче, чтобы не выглядели
  /// крикливо на белом фоне.
  static List<BoxShadow> get neonGlow {
    if (isLight) {
      return [
        BoxShadow(
          color: _p.primary.withValues(alpha: 0.18),
          blurRadius: 18,
          spreadRadius: -2,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: _p.primaryGlow.withValues(alpha: 0.10),
          blurRadius: 28,
          spreadRadius: -4,
          offset: const Offset(0, 14),
        ),
      ];
    }
    return [
      BoxShadow(
        color: _p.primaryGlow.withValues(alpha: 0.5),
        blurRadius: 12,
        spreadRadius: 0,
        offset: Offset.zero,
      ),
      BoxShadow(
        color: _p.primary.withValues(alpha: 0.35),
        blurRadius: 24,
        spreadRadius: -4,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// Сильное свечение (FAB, главные CTA).
  static List<BoxShadow> get neonGlowStrong {
    if (isLight) {
      return [
        BoxShadow(
          color: _p.primary.withValues(alpha: 0.25),
          blurRadius: 22,
          spreadRadius: -2,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: _p.primaryGlow.withValues(alpha: 0.18),
          blurRadius: 36,
          spreadRadius: -6,
          offset: const Offset(0, 18),
        ),
      ];
    }
    return [
      BoxShadow(
        color: _p.primaryGlow.withValues(alpha: 0.6),
        blurRadius: 16,
        spreadRadius: 0,
        offset: Offset.zero,
      ),
      BoxShadow(
        color: _p.primary.withValues(alpha: 0.5),
        blurRadius: 32,
        spreadRadius: -2,
        offset: const Offset(0, 6),
      ),
    ];
  }

  /// Лёгкое свечение (поля ввода в фокусе, мягкие подсветки).
  static List<BoxShadow> get neonGlowSoft {
    if (isLight) {
      return [
        BoxShadow(
          color: _p.primary.withValues(alpha: 0.12),
          blurRadius: 14,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      ];
    }
    return [
      BoxShadow(
        color: _p.primaryGlow.withValues(alpha: 0.25),
        blurRadius: 12,
        spreadRadius: 0,
        offset: Offset.zero,
      ),
    ];
  }

  /// Градиент фона списка чатов.
  static LinearGradient get homeBodyGradient => _p.homeBodyGradient;

  /// Лёгкая подсветка «стекла» для полей поиска и панелей.
  static Color glassOverlay(ColorScheme scheme) {
    final base = scheme.surfaceContainerHighest;
    return base.withValues(alpha: isLight ? 0.7 : 0.45);
  }
}
