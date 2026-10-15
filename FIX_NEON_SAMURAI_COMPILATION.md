# Fix: Exhaustive switch для AppThemeVariant.neonSamurai

## Проблема

Ошибка компиляции в CI/CD:
```
Error: The type 'AppThemeVariant' is not exhaustively matched 
by the switch cases since it doesn't match 'AppThemeVariant.neonSamurai'.
lib/screens/profile_screen.dart:670:13
```

## Причина

Добавили новый enum вариант `AppThemeVariant.neonSamurai`, но в `profile_screen.dart` 
три switch-выражения не учитывали его. Dart требует exhaustive matching для enum.

## Исправление

Добавлены case для `neonSamurai` в три switch в `lib/screens/profile_screen.dart`:

### 1. `_previewColors` (строка ~636)
```dart
case AppThemeVariant.neonSamurai:
  return const [
    Color(0xFF0A0D12),  // Тёмный фон
    Color(0xFF8B5CF6),  // Фиолетовый неон
    Color(0xFFA78BFA),  // Светлый фиолет
  ];
```

### 2. `_accentColor` (строка ~659)
```dart
case AppThemeVariant.neonSamurai:
  return const Color(0xFF8B5CF6);  // Фиолетовый акцент
```

### 3. `_onAccentColor` (строка ~672)
```dart
case AppThemeVariant.neonSamurai:
  return Colors.white;  // Белый текст на фиолетовом
```

## Проверка

```bash
flutter analyze
# 6 issues found (только style info, no errors) ✅
```

Теперь сборка web пройдёт успешно.
