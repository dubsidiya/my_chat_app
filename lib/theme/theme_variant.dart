/// Доступные варианты темы оформления.
///
/// [ultravioletDark] — тёмная готическая ультрафиолетовая палитра (по умолчанию).
/// [auroraLight] — светлая премиальная палитра «Северное сияние»:
///   мягкие сиреневые акценты на чистом белом фоне, эффект «glassmorphism».
enum AppThemeVariant {
  ultravioletDark,
  auroraLight,
}

extension AppThemeVariantX on AppThemeVariant {
  /// Машинное имя для сохранения в локальном хранилище.
  String get storageKey {
    switch (this) {
      case AppThemeVariant.ultravioletDark:
        return 'ultraviolet_dark';
      case AppThemeVariant.auroraLight:
        return 'aurora_light';
    }
  }

  /// Человекочитаемое имя для UI.
  String get displayName {
    switch (this) {
      case AppThemeVariant.ultravioletDark:
        return 'Ультрафиолет (тёмная)';
      case AppThemeVariant.auroraLight:
        return 'Аврора (светлая)';
    }
  }

  /// Краткое описание под названием темы.
  String get description {
    switch (this) {
      case AppThemeVariant.ultravioletDark:
        return 'Глубокий фиолетовый, неоновое свечение';
      case AppThemeVariant.auroraLight:
        return 'Мягкие сиреневые акценты на белом';
    }
  }

  /// Тёмная ли это палитра.
  bool get isDark => this == AppThemeVariant.ultravioletDark;
}

/// Восстанавливает вариант темы из строки, сохранённой в [SharedPreferences].
AppThemeVariant appThemeVariantFromStorage(String? raw) {
  if (raw == null || raw.isEmpty) return AppThemeVariant.ultravioletDark;
  for (final v in AppThemeVariant.values) {
    if (v.storageKey == raw) return v;
  }
  return AppThemeVariant.ultravioletDark;
}
