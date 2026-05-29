# Промпт: модернизация UI (my_chat_app / reollity)

Используй этот чеклист при перенастройке внешнего вида клиента к более современному и стильному решению.

## Цель

Обновить визуальный язык Flutter-клиента: более современный, цельный и «премиальный» интерфейс **без** изменения бизнес-логики, API-контрактов и навигации.

**Результат:** единая дизайн-система, меньше хардкода цветов в экранах, улучшенная типографика, spacing, состояния (loading/empty/error), анимации там, где они усиливают UX — особенно в чатах, auth и табах.

---

## Контекст проекта (не переизобретать)

- **Стек:** Flutter (iOS, Android, Web), Material 3.
- **Тема:** `lib/theme/` — `app_theme.dart`, `app_colors.dart`, `theme_variant.dart`, `theme_controller.dart`.
- **Варианты тем:** `ultravioletDark` (по умолчанию), `auroraLight` — обе должны остаться и выглядеть согласованно.
- **Точка входа:** `lib/main.dart` → `MaterialApp` + `ThemeController`.
- **Ключевые экраны:** `lib/screens/` (чаты, auth, студенты, отчёты, бухгалтерия).
- **Переиспользуемые виджеты чата:** `lib/widgets/chat_*.dart`, `fade_scale_in.dart`, `skeleton_placeholder.dart`.
- **Skill архитектуры:** `.cursor/skills/my-chat-app-architecture/SKILL.md`.
- **Правила:** `.cursor/rules/project-workflow.mdc` — после Dart-правок обязательно `flutter analyze` на изменённых файлах.

---

## Направление дизайна (ориентиры)

Сохранить фиолетово-неоновую идентичность бренда, но подтянуть до уровня современных мессенджеров и productivity-приложений 2025–2026:

| Область | Сейчас (проблема) | Целевое состояние |
|--------|-------------------|-------------------|
| **Палитра** | Много `Color(0x…)` / `Colors.*` в экранах | Все цвета через `AppColors` + `ColorScheme`; семантические токены (surface, elevated, muted, accent) |
| **Поверхности** | Плоские карточки с border | Мягкая глубина: elevation/blur/glass на светлой теме; тонкие градиенты на тёмной |
| **Типографика** | Системный шрифт без характера | Один display/body шрифт (например Inter / SF / Google Fonts), чёткая шкала заголовков |
| **Spacing** | Разрозненные padding | 4/8/12/16/24/32 grid; единые отступы ListTile, Card, Dialog |
| **Скругления** | 14–22 без системы | Токены: `radiusSm=10`, `radiusMd=14`, `radiusLg=20`, `radiusPill=999` |
| **Чат** | Пузыри, input bar, reactions | Telegram/iMessage-подобная читаемость: контраст, группировка, sticky date, composer с blur |
| **Auth** | Отдельный стиль login/register | Единый hero + форма; микро-анимации (fade/scale уже есть в `fade_scale_in.dart`) |
| **Empty/Loading** | Разные паттерны | Единые `EmptyState`, skeleton через `skeleton_placeholder.dart` |
| **Motion** | Минимум | Короткие (150–250 ms) переходы; `page_routes.dart`; без тяжёлых анимаций на списках |

**Референсы по духу (не копировать 1:1):** Telegram, Linear, Notion mobile, iOS Messages — чистота, воздух, читаемость.

---

## Ограничения (обязательно)

1. **Не менять:** API, сервисы (`lib/services/`), модели, WebSocket, права доступа к отчётам, тексты ошибок с сервером.
2. **Не трогать:** `.env`, секреты, бэкенд (если задача только UI).
3. **Минимальный diff:** не рефакторить экраны «заодно»; только UI-слой.
4. **Доступность:** контраст WCAG AA для body-текста; hit area ≥ 44×44 на мобильных.
5. **Web + mobile:** проверить, что glass/blur имеет fallback без `BackdropFilter` там, где ломает perf.
6. **Две темы:** любое изменение палитры — сразу для `ultravioletDark` и `auroraLight`.
7. **Локализация:** не менять русские строки без запроса; не ломать длинные подписи в отчётах/бухгалтерии.

---

## Приоритеты (фазы)

Выполнять **по одной фазе за сессию**, в конце каждой — `flutter analyze` + визуальная проверка 2–3 ключевых экранов.

### Фаза 0 — Design tokens (фундамент)

- Расширить `lib/theme/`: `app_spacing.dart`, `app_radius.dart`, `app_shadows.dart` (или секции в существующих файлах).
- Добавить семантические цвета в `app_colors.dart`: `messageOutgoing`, `messageIncoming`, `online`, `offline`, `dividerSubtle`.
- Обновить `buildAppTheme()` в `app_theme.dart`: NavigationBar, SegmentedButton, Badge, Tooltip, если используются.

### Фаза 1 — Чат (максимальный visual impact)

- `lib/widgets/chat_message_tile.dart` — убрать хардкод, группировка пузырей, tail, время/read receipts.
- `lib/widgets/chat_input_bar.dart`, `chat_screen_typing_composer.dart`, `chat_date_header.dart`, `chat_empty_messages.dart`.
- `lib/screens/chat_screen.dart` — AppBar, фон, search overlay (`chat_screen_search.dart`).

### Фаза 2 — Home + навигация

- `lib/screens/home_screen.dart`, `home_dialogs.dart` — список чатов, swipe actions, unread badge.
- `lib/screens/main_tabs_screen.dart` — bottom nav / tabs в едином стиле.

### Фаза 3 — Auth + профиль

- `lib/screens/login_screen.dart`, `register_screen.dart` — сейчас много прямых `AppColors` (~47–48 usages); унифицировать.
- `lib/screens/profile_screen.dart`, `user_profile_screen.dart`.

### Фаза 4 — Студенты, отчёты, бухгалтерия

- `students_screen.dart`, `student_detail_screen.dart`, `report_builder_screen.dart`, `accounting_export_screen.dart`.
- Сохранить текущие паттерны permission UI (скрытие кнопок по роли) — только визуал.

### Фаза 5 — Полировка

- Заменить оставшийся хардкод: `grep -r "Color(0x" lib/`, `grep -r "Colors\." lib/screens lib/widgets`.
- Унифицировать SnackBar, Dialog, BottomSheet через theme (уже частично в `app_theme.dart`).

---

## Технический подход

1. **Сначала прочитать** `@lib/theme/app_theme.dart`, `@lib/theme/app_colors.dart`, `@.cursor/skills/my-chat-app-architecture/SKILL.md`.
2. **Новые UI-примитивы** — только если повторяются ≥3 раза:
   - `lib/widgets/ui/app_card.dart`
   - `lib/widgets/ui/section_header.dart`
   - `lib/widgets/ui/empty_state.dart`
   Не плодить абстракции для одноразовых случаев.
3. **Шрифт:** если добавляешь `google_fonts` — одна точка подключения в `app_theme.dart`, fallback на системный.
4. **Анимации:** переиспользовать `fade_scale_in.dart`; для списков — только при первом появлении, не на каждый rebuild.
5. **Светлая тема «Аврора»:** glassmorphism — `BackdropFilter` + полупрозрачный `surface`; на Android проверить perf.

---

## Anti-patterns

- Не переписывать `StatefulWidget` → `Riverpod/Bloc` ради UI.
- Не менять структуру папок `features/` без необходимости.
- Не вводить тяжёлые пакеты (Lottie, Rive, Shimmer) без явной пользы — сначала `skeleton_placeholder.dart`.
- Не делать «редизайн всего приложения» в одном PR — только одна фаза.
- Не хардкодить `#7C3AED` в экранах — только токены темы.

---

## Верификация (Definition of Done)

- [ ] `flutter analyze` — 0 issues на изменённых файлах
- [ ] Обе темы (`ultravioletDark`, `auroraLight`) переключаются в профиле без артефактов
- [ ] Ручная проверка: Login → Home → Chat (отправка/ответ) → Profile → Students (если фаза затрагивает)
- [ ] Web: список чатов и composer не «плывут» по ширине
- [ ] Нет новых `Color(0x` / `Colors.` в изменённых экранах (кроме `app_colors.dart`)
- [ ] Отчёты/бухгалтерия: видимость действий по роли не изменилась

---

## Формат ответа агента

1. Краткий план (какая фаза, какие файлы).
2. Изменения с обоснованием дизайн-решений.
3. Список изменённых файлов.
4. Результат `flutter analyze`.
5. Скриншоты / описание «до/после» по ключевым экранам (если доступен эмулятор).
6. Что осталось на следующую фазу.

---

## Стартовая команда для чата

```
@.cursor/skills/my-chat-app-architecture/SKILL.md
@lib/theme/app_theme.dart
@lib/theme/app_colors.dart
@lib/widgets/chat_message_tile.dart
@lib/screens/home_screen.dart

Выполни Фазу 0 + Фазу 1 промпта UI-модернизации:
- design tokens в lib/theme/
- редизайн чата (пузыри, composer, date header, empty state)
- сохрани ultravioletDark и auroraLight
- не трогай services/ и backend
- flutter analyze в конце
```

---

## Как использовать

| Шаг | Действие |
|-----|----------|
| 1 | Новый чат → вставить промпт + `@`-файлы из «Стартовой команды» |
| 2 | Указать фазу (0–5) или «Фаза 0 + 1» |
| 3 | При необходимости добавить референс: «ближе к Telegram» / «больше glass на светлой» |
| 4 | После каждой фазы — новый чат для следующей, чтобы контекст оставался коротким |
