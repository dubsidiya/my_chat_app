import 'package:flutter/widgets.dart';

/// Единые токены отступов, скруглений и анимаций приложения.
///
/// Цель — убрать «магические числа» из экранов и держать единый ритм:
/// все отступы кратны 4, скругления и длительности анимаций берутся из
/// общего набора. Это часть дизайн-системы (см. `app_colors.dart`,
/// `app_theme.dart`).

/// Сетка отступов — уменьшена на ~20% для более компактного современного вида
/// Применяется ко всем экранам для единого ритма
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;  // минимальный отступ
  static const double xs = 4;   // 5 → 4
  static const double sm = 6;   // 8 → 6
  static const double md = 10;  // 12 → 10
  static const double lg = 13;  // 16 → 13
  static const double xl = 19;  // 24 → 19
  static const double xxl = 26; // 32 → 26
  static const double huge = 38;// 48 → 38

  static const EdgeInsets allXs = EdgeInsets.all(xs);
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);
  static const EdgeInsets allXl = EdgeInsets.all(xl);

  /// Горизонтальный паддинг контента экрана по умолчанию
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: lg);
  
  /// Вертикальный паддинг секций
  static const EdgeInsets sectionV = EdgeInsets.symmetric(vertical: md);
}

/// Шкала скруглений для премиум feel
/// Применяется единообразно для создания визуального ритма
class AppRadius {
  AppRadius._();

  static const double xs = 6;   // минимальное скругление
  static const double sm = 8;   // chip, small card
  static const double md = 11;  // standard card
  static const double lg = 16;  // large card, dialog
  static const double xl = 22;  // bottom sheet, modal
  static const double pill = 999; // pills, chips, badges

  static BorderRadius get xsAll => BorderRadius.circular(xs);
  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);

  /// Верхнее скругление для bottom sheet
  static BorderRadius get sheetTop =>
      const BorderRadius.vertical(top: Radius.circular(xl));
  
  /// Bento-стиль: разное скругление для разнообразия
  static BorderRadius bentoVariant(int index) {
    final radii = [md, lg, md, sm, lg];
    return BorderRadius.circular(radii[index % radii.length]);
  }
}

/// Длительности анимаций с spring-based feel
/// Следует принципам Material 3 Expressive
class AppMotion {
  AppMotion._();

  // Базовые длительности
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration xslow = Duration(milliseconds: 450);

  // Кривые для различных типов движения
  static const Curve curve = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
  static const Curve spring = Curves.easeOutExpo; // имитация spring
  
  /// Staggered entrance: index * delay
  static Duration stagger(int index, {Duration base = fast}) {
    return Duration(milliseconds: base.inMilliseconds + (index * 50));
  }
}
