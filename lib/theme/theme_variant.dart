/// Доступные варианты темы оформления.
///
/// [ultravioletDark] — тёмная готическая ультрафиолетовая палитра (по умолчанию).
/// [auroraLight] — светлая премиальная палитра «Северное сияние».
/// [oceanPulse] — тёмная океаническая: navy + бирюза, с мягким «дыханием» UI.
enum AppThemeVariant {
  ultravioletDark,
  auroraLight,
  oceanPulse,
}

extension AppThemeVariantX on AppThemeVariant {
  /// Машинное имя для сохранения в локальном хранилище.
  String get storageKey {
    switch (this) {
      case AppThemeVariant.ultravioletDark:
        return 'ultraviolet_dark';
      case AppThemeVariant.auroraLight:
        return 'aurora_light';
      case AppThemeVariant.oceanPulse:
        return 'ocean_pulse';
    }
  }

  /// Человекочитаемое имя для UI.
  String get displayName {
    switch (this) {
      case AppThemeVariant.ultravioletDark:
        return 'Ультрафиолет (тёмная)';
      case AppThemeVariant.auroraLight:
        return 'Аврора (светлая)';
      case AppThemeVariant.oceanPulse:
        return 'Океанский пульс';
    }
  }

  /// Краткое описание под названием темы.
  String get description {
    switch (this) {
      case AppThemeVariant.ultravioletDark:
        return 'Глубокий фиолетовый, неоновое свечение';
      case AppThemeVariant.auroraLight:
        return 'Мягкие сиреневые акценты на белом';
      case AppThemeVariant.oceanPulse:
        return 'Navy и бирюза, живое дыхание интерфейса';
    }
  }

  /// Тёмная ли это палитра.
  bool get isDark => this != AppThemeVariant.auroraLight;

  /// Включены ли motion-эффекты темы (волна фона, пульс online и т.п.).
  bool get hasMotion => this == AppThemeVariant.oceanPulse;
}

/// Восстанавливает вариант темы из строки, сохранённой в [SharedPreferences].
AppThemeVariant appThemeVariantFromStorage(String? raw) {
  if (raw == null || raw.isEmpty) return AppThemeVariant.ultravioletDark;
  for (final v in AppThemeVariant.values) {
    if (v.storageKey == raw) return v;
  }
  return AppThemeVariant.ultravioletDark;
}
