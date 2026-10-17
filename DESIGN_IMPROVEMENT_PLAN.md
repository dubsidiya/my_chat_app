# План кардинального улучшения дизайна приложения

## Цель
Поднять дизайн с "стандартного Material" до "премиум digital product" с применением паттернов из flutter-taste-skill, mobile-design-android и современных трендов.

## Установленные скилы
✅ flutter-taste-skill — bento grids, glassmorphism, mesh gradients, anti-slop паттерны
✅ mobile-design-android — Material 3 Expressive, spring physics, 48 color roles
✅ mobile-design-ios — iOS 26 Liquid Glass (для референса cross-platform паттернов)

## Новые дизайн-токены
✅ `/lib/theme/app_design_tokens.dart` — glassmorphism, neon glows, mesh gradients
✅ Обновлён `app_dimens.dart` — компактность +20%, bento variants, staggered animations

## Приоритет улучшения экранов

### 1. Home Screen (список чатов) — HIGH PRIORITY
**Текущее состояние**: Стандартный ListView с одинаковыми карточками

**Улучшения**:
- ✅ Glassmorphism для search bar с inner border 1px
- ✅ Bento grid вместо однообразных карточек (разные высоты/ширины)
- ✅ Staggered entrance animations (index * 50ms delay)
- ✅ Mesh gradient background вместо простого LinearGradient
- ✅ Neon glow для unread badges
- ✅ Spring-based animations при tap (scale to 0.97)
- ✅ Compound shadows вместо flat elevation

**Файлы**: `lib/screens/home_screen.dart`, `lib/widgets/skeleton_placeholder.dart`

### 2. Chat Screen (сообщения) — HIGH PRIORITY
**Текущее состояние**: Стандартные message bubbles

**Улучшения**:
- Inner borders 1px для всех message bubbles
- Glassmorphism для input bar
- Улучшенная типографика (emphasized variants)
- Spring animations при отправке сообщения
- Mesh gradient для background
- Improved spacing (компактность)
- Voice message bubbles с waveform visualization

**Файлы**: `lib/screens/chat_screen.dart`, `lib/widgets/chat_message_tile.dart`

### 3. Login/Register Screens — MEDIUM PRIORITY
**Текущее состояние**: Простые градиенты

**Улучшения**:
- Mesh gradient backgrounds (overlapping radial gradients)
- Glassmorphism для input fields с backdrop blur
- Neon glows для CTA buttons
- Staggered entrance для form fields
- Improved spacing и typography
- Premium feel без "AI purple" (#7C3AED ban)

**Файлы**: `lib/screens/login_screen.dart`, `lib/screens/register_screen.dart`

### 4. Profile Screen — MEDIUM PRIORITY
**Улучшения**:
- Bento layout для stats/settings cards
- Glassmorphism для avatar container
- Compound expressiveness: shape + color + spring + emphasized typography
- Mesh overlay background

**Файлы**: `lib/screens/profile_screen.dart`

### 5. Students/Reports Screens — LOW PRIORITY
**Улучшения**:
- Dashboard density (FLUTTER_DENSITY: 7)
- Data visualization с mesh backgrounds
- Glassmorphism для data cards
- Improved table/list layouts

**Файлы**: `lib/screens/students_screen.dart`, `lib/screens/reports_chat_screen.dart`

## Принципы улучшения

### Flutter Taste Skill — Anti-Slop Rules
1. ❌ **EM-DASH BAN** — нельзя использовать `—` или `–`
2. ❌ **Boilerplate Ban** — никаких "Hello World", "Sample Item"
3. ❌ **AI-Purple Ban** — запрет `#7C3AED` и indigo-purple градиентов
4. ❌ **Default Scaffold Ban** — никогда default Scaffold без custom styling

### Обязательные элементы
1. ✅ **Inner borders 1px** — `Colors.white.withValues(alpha: 0.1)` для всех glassmorphism карточек
2. ✅ **Staggered animations** — `index * 50ms` delay для entrance
3. ✅ **Theme.of(context).colorScheme** — использовать ВЕЗДЕ вместо hardcoded colors
4. ✅ **Compound shadows** — ambient + directional вместо простого elevation
5. ✅ **Mesh gradients** — multiple overlapping radial gradients для backgrounds
6. ✅ **Spring feel** — easeOutExpo curves вместо linear tweens

### Параметры дизайна
- **VARIANCE: 7** — bento grids, asymmetric padding, Stack overlays
- **MOTION: 6** — staggered entrance, press feedback scale(0.97)
- **DENSITY: 5** — стандартная mobile плотность (16-20px padding)

## Следующие шаги
1. ✅ Создать design tokens (`app_design_tokens.dart`)
2. ✅ Обновить `app_dimens.dart`
3. 🔄 Улучшить Home Screen (список чатов)
4. ⏳ Улучшить Chat Screen (сообщения)
5. ⏳ Улучшить Auth screens
6. ⏳ Улучшить Profile screen
7. ⏳ Smoke test всех экранов

## Верификация
После каждого экрана:
```bash
flutter analyze lib/screens/<changed_screen>.dart
```

После всех изменений:
```bash
flutter run
# Manual testing на iOS/Android simulators
```

## Примечания
- Сохранить все функциональность — только визуальные улучшения
- Не трогать логику шифрования (E2EE)
- Не изменять API calls
- Сохранить accessibility (contrast ratios, touch targets)
