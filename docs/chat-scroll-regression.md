# Автоматический аудит поведения скролла чата

Запуск одной командой (локально или в CI):

```bash
bash scripts/test-chat-scroll-regression.sh
```

## Что проверяется автоматически

| Слой | Файл | Что покрыто |
|------|------|-------------|
| Unit | `test/chat/chat_scroll_policy_test.dart` | Базовая политика скролла |
| Matrix | `test/chat/chat_scroll_regression_matrix_test.dart` | 13+ сценариев из каталога |
| Widget | `test/chat/chat_open_scroll_widget_test.dart` | Открытие, load-more, prepend, медиа-layout |
| Widget | `test/chat/chat_message_tile_media_layout_test.dart` | Placeholder фото 250×400 |
| Catalog | `test/chat/fixtures/chat_scroll_scenarios.dart` | Именованные сценарии для расширения |

## Промпт для Cursor Agent (полная автоматизация)

Скопируй в новый Agent-чат:

---

**Задача:** regression-аудит скролла чата. Работай только через автоматические проверки.

**Шаг 1.** Запусти:
```bash
bash scripts/test-chat-scroll-regression.sh
```

**Шаг 2.** Если есть падения:
- прочитай stack trace;
- найди root cause в `lib/features/chat/chat_scroll_policy.dart`, `lib/screens/chat_screen_scroll.dart`, `lib/screens/chat_screen_messages_sync.dart`, `lib/widgets/chat_message_tile.dart`;
- исправь минимальным diff;
- если новый edge case — добавь тест в `test/chat/chat_scroll_regression_matrix_test.dart` или `test/chat/chat_open_scroll_widget_test.dart` и строку в `test/chat/fixtures/chat_scroll_scenarios.dart`;
- перезапусти скрипт до зелёного статуса.

**Шаг 3.** Дополнительно прогони:
```bash
flutter analyze lib/screens/chat_screen*.dart
flutter test test/chat/
```

**Шаг 4.** Отчёт только в формате:
- `PASS/FAIL` по каждому файлу тестов
- список исправлений (если были)
- новые сценарии в matrix (если добавлял)
- что **не** покрыто автоматикой: push deep link, real WebSocket, legacy key-exchange UI (см. `.cursor/rules/chat-encryption-model.mdc`)

**Ограничения:** не коммить, не трогать secrets/env, не менять unrelated код.

**Критерий done:** `bash scripts/test-chat-scroll-regression.sh` exit 0.

---

## Как добавить новый сценарий

1. Добавь `ChatScrollScenario` в `test/chat/fixtures/chat_scroll_scenarios.dart`
2. Добавь unit-case в `test/chat/chat_scroll_regression_matrix_test.dart`
3. Если нужен layout/scroll — добавь widget-case в `test/chat/chat_open_scroll_widget_test.dart`
4. Запусти `bash scripts/test-chat-scroll-regression.sh`

## Что автоматика не покрывает (нужен manual / integration_test позже)

- Push notification → открытие чата
- WebSocket burst сообщений
- iOS/Android/Web платформенные отличия
- Pin bar + keyboard overlay
- Legacy key-exchange UI (не основной путь; см. `.cursor/rules/chat-encryption-model.mdc`)

Для этих случаев можно позже добавить `integration_test/` с mock backend.
