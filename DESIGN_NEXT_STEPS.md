# Следующие шаги по улучшению дизайна

## Что уже сделано ✅

1. **Установлены профессиональные дизайн-скилы**:
   - `flutter-taste-skill` — bento grids, glassmorphism, mesh gradients
   - `mobile-design-android` — Material 3 Expressive, spring physics
   - `mobile-design-ios` — iOS 26 Liquid Glass (референс)

2. **Созданы новые дизайн-токены**:
   - `/lib/theme/app_design_tokens.dart` — glassmorphism, neon glows, mesh gradients
   - Обновлён `/lib/theme/app_dimens.dart` — компактность, bento variants, staggered animations

3. **План улучшения**:
   - Создан `/DESIGN_IMPROVEMENT_PLAN.md` с детальным планом улучшения всех экранов

## Что нужно сделать дальше 🔄

### 1. Home Screen (приоритет #1)

Обновить `/lib/screens/home_screen.dart`:

```dart
import '../theme/app_design_tokens.dart';
```

**Улучшения**:
- Строка 2120-2185: Search bar → заменить на glassmorphism с `AppDesignTokens.glassCard()`
- Строка 770-945: Chat tiles → добавить staggered animations с `AppDesignTokens.staggerDelay(index)`
- Строка 2068-2370: Background → добавить mesh gradient с `AppDesignTokens.meshOverlay()`
- Строка 905-940: Unread badge → использовать `AppDesignTokens.neonGlow()`

**Пример кода для search bar**:
```dart
Container(
  decoration: AppDesignTokens.glassCard(scheme, alpha: 0.15, borderAlpha: 0.1),
  child: TextField(
    controller: _searchController,
    onChanged: _onSearchChanged,
    decoration: InputDecoration(
      hintText: 'Поиск по чатам',
      border: InputBorder.none,
      // ... остальное
    ),
  ),
)
```

**Пример staggered animation для chat tile**:
```dart
return FadeScaleIn(
  delay: AppDesignTokens.staggerDelay(index),
  child: Dismissible(
    // ... существующий код
  ),
);
```

### 2. Chat Screen

Обновить `/lib/widgets/chat_message_tile.dart`:

- Добавить inner borders для message bubbles
- Применить glassmorphism для input bar
- Улучшить spacing с использованием `AppSpacing` констант

### 3. Login/Register Screens

- Mesh gradient backgrounds
- Glassmorphism input fields
- Neon glows для CTA buttons

## Команды для проверки

После каждого изменения:
```bash
# Проверка синтаксиса
flutter analyze lib/screens/home_screen.dart

# Запуск приложения
flutter run

# Проверка на конкретных экранах
```

## Принципы (из flutter-taste-skill)

### Anti-Slop Ban List (КРИТИЧНО):
1. ❌ EM-DASH BAN — нельзя `—` или `–`
2. ❌ Boilerplate Ban — никаких "Hello World"
3. ❌ AI-Purple Ban — запрет `#7C3AED`
4. ❌ Scaffold Default Ban — всегда custom styling

### Обязательные элементы:
1. ✅ Inner borders 1px для glassmorphism
2. ✅ Staggered animations (index * 50ms)
3. ✅ Theme.of(context).colorScheme везде
4. ✅ Compound shadows вместо elevation
5. ✅ Mesh gradients для backgrounds

## Dial Settings
- **VARIANCE: 7** — bento grids, asymmetric layout
- **MOTION: 6** — staggered entrance, press feedback
- **DENSITY: 5** — standard mobile (16-20px)

## Важно
- Сохранить всю функциональность
- Не трогать E2EE логику
- Не изменять API calls
- Сохранить accessibility
