import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'theme_variant.dart';

/// Строит [ThemeData] для указанного варианта темы.
///
/// На вход поступает [variant], а внутри метод собирает соответствующую
/// палитру (через [AppColors]) и формирует Material 3 тему. Все компоненты
/// (AppBar, Card, Dialog, Inputs, Buttons и т.д.) настраиваются единообразно,
/// чтобы переключение темы корректно работало во всех экранах.
ThemeData buildAppTheme(AppThemeVariant variant) {
  // Активируем палитру до того, как начнём читать AppColors.
  AppColors.setActiveVariant(variant);

  final isLight = variant == AppThemeVariant.auroraLight;
  final brightness = isLight ? Brightness.light : Brightness.dark;

  final scheme = isLight
      ? ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: AppColors.cardElevatedDark,
          onPrimaryContainer: AppColors.primaryDeep,
          secondary: AppColors.primaryGlow,
          onSecondary: Colors.white,
          surface: AppColors.surfaceDark,
          onSurface: AppColors.onSurfaceDark,
          onSurfaceVariant: AppColors.onSurfaceVariantDark,
          outline: AppColors.borderDark,
          surfaceContainerHighest: AppColors.cardDark,
          error: AppColors.errorDark,
          onError: Colors.white,
        )
      : ColorScheme.dark(
          primary: AppColors.primary,
          onPrimary: AppColors.onSurfaceDark,
          primaryContainer: AppColors.cardElevatedDark,
          onPrimaryContainer: AppColors.accent,
          secondary: AppColors.primaryGlow,
          onSecondary: AppColors.backgroundDark,
          surface: AppColors.surfaceDark,
          onSurface: AppColors.onSurfaceDark,
          onSurfaceVariant: AppColors.onSurfaceVariantDark,
          outline: AppColors.borderDark,
          surfaceContainerHighest: AppColors.cardDark,
          error: AppColors.errorDark,
          onError: Colors.white,
        );

  final surface = AppColors.surfaceDark;
  final card = AppColors.cardDark;
  final outline = AppColors.borderDark;

  // Базовая типография: на светлой теме берём blackMountainView, на тёмной —
  // whiteMountainView. Эти базы дают правильные цвета по умолчанию.
  final baseText = isLight
      ? Typography.blackMountainView
      : Typography.whiteMountainView;

  final textTheme = baseText
      .apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        displayLarge: baseText.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.15,
        ),
        displayMedium: baseText.displayMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
        ),
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          height: 1.25,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 22,
          height: 1.25,
          letterSpacing: -0.15,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 17,
          height: 1.3,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(
          height: 1.45,
          fontSize: 16,
        ),
        bodyMedium: baseText.bodyMedium?.copyWith(
          height: 1.4,
          fontSize: 14,
        ),
        bodySmall: baseText.bodySmall?.copyWith(
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
        labelLarge: baseText.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.25,
        ),
      );

  // Цвет иконок системы: на светлой теме — тёмные, на тёмной — светлые.
  final overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
    statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: AppColors.surfaceDark,
    systemNavigationBarIconBrightness:
        isLight ? Brightness.dark : Brightness.light,
  );

  // Цвет AppBar в обеих темах визуально совпадает с основным фоном экранов.
  final appBarBackground = AppColors.backgroundDark;

  // Параметры карточек: в светлой теме нужна еле заметная тень, тёмная —
  // обходится мягкой пурпурной подсветкой.
  final cardShadow = isLight
      ? Colors.black.withValues(alpha: 0.06)
      : AppColors.primary.withValues(alpha: 0.08);

  // Подсветка для disabled-состояний и Splash.
  final hoverColor = AppColors.primary.withValues(alpha: isLight ? 0.06 : 0.10);
  final splashColor =
      AppColors.primaryGlow.withValues(alpha: isLight ? 0.10 : 0.18);

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    primaryColor: scheme.primary,
    scaffoldBackgroundColor: surface,
    cardColor: card,
    dividerColor: outline,
    visualDensity: VisualDensity.standard,
    useMaterial3: true,
    textTheme: textTheme,
    hoverColor: hoverColor,
    splashColor: splashColor,
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurface.withValues(alpha: 0.85),
      textColor: scheme.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      dense: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.primary.withValues(alpha: isLight ? 0.10 : 0.14),
      selectedColor: AppColors.primary.withValues(alpha: isLight ? 0.22 : 0.32),
      disabledColor: scheme.onSurface.withValues(alpha: 0.08),
      labelStyle:
          TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(color: scheme.onSurface),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: outline.withValues(alpha: 0.5)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: isLight ? AppColors.primaryDeep : AppColors.accent,
      unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.58),
      indicatorColor: AppColors.primaryGlow,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: AppColors.primary.withValues(alpha: 0.12),
      backgroundColor: appBarBackground,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      systemOverlayStyle: overlay,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        letterSpacing: -0.1,
      ),
      iconTheme:
          IconThemeData(color: scheme.onSurface.withValues(alpha: 0.92), size: 24),
    ),
    cardTheme: CardThemeData(
      elevation: isLight ? 0 : 0,
      color: card,
      shadowColor: cardShadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: outline.withValues(alpha: isLight ? 0.55 : 0.28),
          width: 1,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      elevation: isLight ? 8 : 16,
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: AppColors.primaryGlow.withValues(alpha: isLight ? 0.30 : 0.45),
        ),
      ),
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        letterSpacing: -0.15,
      ),
      contentTextStyle: TextStyle(
        fontSize: 15,
        height: 1.4,
        color: scheme.onSurface.withValues(alpha: 0.9),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: card,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: outline.withValues(alpha: 0.6)),
      ),
      showDragHandle: true,
      dragHandleColor:
          AppColors.primaryGlow.withValues(alpha: isLight ? 0.40 : 0.55),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: outline.withValues(alpha: 0.5)),
      ),
      textStyle: TextStyle(color: scheme.onSurface, fontSize: 15),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      backgroundColor: AppColors.cardElevatedDark,
      contentTextStyle: TextStyle(
        color: AppColors.onSurfaceDark,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: outline.withValues(alpha: 0.35)),
      ),
      showCloseIcon: true,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.primaryGlow,
      linearTrackColor: AppColors.primary.withValues(alpha: 0.15),
      circularTrackColor: AppColors.primary.withValues(alpha: 0.12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest
          .withValues(alpha: isLight ? 0.9 : 0.55),
      hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.45)),
      labelStyle:
          TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline.withValues(alpha: 0.32)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline.withValues(alpha: 0.22)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primaryGlow, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: AppColors.primary,
        foregroundColor: isLight ? Colors.white : AppColors.onSurfaceDark,
        padding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: outline.withValues(alpha: 0.65)),
        foregroundColor: scheme.onSurface,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        foregroundColor: AppColors.primaryGlow,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurface.withValues(alpha: 0.88),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: outline.withValues(alpha: isLight ? 0.6 : 0.25),
      thickness: 1,
      space: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: isLight ? Colors.white : AppColors.onSurfaceDark,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primaryGlow;
        return isLight ? Colors.white : AppColors.onSurfaceVariantDark;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary.withValues(alpha: isLight ? 0.55 : 0.65);
        }
        return outline.withValues(alpha: isLight ? 0.5 : 0.35);
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return scheme.onSurfaceVariant;
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: BorderSide(color: outline.withValues(alpha: 0.6), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
  );
}
