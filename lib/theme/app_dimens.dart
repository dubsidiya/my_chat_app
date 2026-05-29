import 'package:flutter/widgets.dart';

/// Единые токены отступов, скруглений и анимаций приложения.
///
/// Цель — убрать «магические числа» из экранов и держать единый ритм:
/// все отступы кратны 4, скругления и длительности анимаций берутся из
/// общего набора. Это часть дизайн-системы (см. `app_colors.dart`,
/// `app_theme.dart`).

/// Сетка отступов 4 / 8 / 12 / 16 / 24 / 32.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);

  /// Горизонтальный паддинг контента экрана по умолчанию.
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: lg);
}

/// Шкала скруглений. `pill` — для капсул/чипов, `xl` — для модальных листов.
class AppRadius {
  AppRadius._();

  static const double xs = 8;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static BorderRadius get xsAll => BorderRadius.circular(xs);
  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);

  /// Верхнее скругление для bottom sheet.
  static BorderRadius get sheetTop =>
      const BorderRadius.vertical(top: Radius.circular(xl));
}

/// Длительности анимаций: короткие переходы ощущаются «отзывчиво».
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve curve = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
}
