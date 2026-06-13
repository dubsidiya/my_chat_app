---
name: my-chat-app-architecture
description: >-
  Describes the reollity / my_chat_app monorepo: Flutter chat client plus Node
  Express PostgreSQL WebSocket backend, main folders, and where to change
  behavior. Use when the user asks how the app is structured, where logic lives,
  which service touches the API, or when starting any feature/bugfix across
  client and server without re-explaining the whole project.
disable-model-invocation: true
---

# My Chat App — архитектура репозитория

Не спрашивать пользователя «как устроен проект» с нуля: опираться на этот skill и при необходимости читать указанные файлы.

## Продукт и стек

- **Название в README:** reollity. Пакет Flutter: `my_chat_app` (`pubspec.yaml`).
- **Клиент:** Flutter (iOS, Android, Web) — корень репо.
- **Сервер:** `my_serve_chat_test/` — Node.js (ES modules), Express, PostgreSQL (`pg`), WebSocket (`ws`), JWT, часть загрузок через S3-совместимое API (Yandex Object Storage и т.п. по конфигу).
- **Клиентские сервисы:** Firebase (push), Hive (кэш сообщений), `flutter_secure_storage` (токен), шифрование чата (`E2eeService` — **legacy-имя**, см. ниже).

## Шифрование чатов — важно (не настоящий E2EE)

**Не предполагать, что E2EE в проекте работает как в Signal/Telegram Secret.**

- **Production-модель:** сервер хранит `chats.shared_chat_key` (plaintext) и отдаёт участникам через `GET /e2ee/chat/:chatId/shared-key`. Клиент: `E2eeService._fetchSharedChatKey()` — **первый** путь в `getChatKey()`.
- **Legacy fallback:** X25519 + `chat_keys`, WS key request — для старых чатов без shared key. Часто даёт «E2EE сломан» / ожидание ключа / 429.
- **Документы `docs/E2EE_*.md`** в основном про legacy; актуальная картина — `docs/LOGIC_AUDIT_2026-06-02.md` (раздел про server-held key).
- **Правило Cursor:** `.cursor/rules/chat-encryption-model.mdc` (alwaysApply).

При багах «не расшифровывается / нет ключа» — сначала shared-key API и создание чата, не key exchange между пользователями.

## Где что лежит (Flutter — `lib/`)

| Область | Папка / файлы |
|--------|----------------|
| Точка входа, тема | `main.dart`, `theme/` |
| API base URL | `config/api_config.dart` (и `--dart-define=API_BASE_URL=...`) |
| HTTP / обёртки | `services/http_service.dart`, `utils/timed_http.dart` |
| Чаты, сообщения, WS | `services/chats_service.dart`, `services/messages_service.dart`, `services/websocket_service.dart`, `services/local_messages_service.dart` |
| Отчёты (зарплата, бухгалтерия UI) | `services/reports_service.dart`, `features/reports/`, экраны `*report*`, `monthly_salary_*`, `accounting_*` |
| Студенты, уроки, депозиты | `services/students_service.dart`, `features/students/`, экраны `students_*`, `*lesson*`, `deposit_*` |
| Аутентификация | `features/auth/`, `services/auth_service.dart`, `screens/login_screen.dart`, `register_screen.dart` |
| Модерация | `features/moderation/`, `services/moderation_service.dart` |
| E2EE / медиа | `services/e2ee_service.dart`, `widgets/e2ee_image.dart` — см. раздел «Шифрование чатов» выше |
| Модели | `models/` |
| Экраны | `screens/` |
| Навигация / табы | `screens/main_tabs_screen.dart`, `utils/page_routes.dart` |

Фичи часто разбиты на `features/<name>/` + соответствующие `services/*_service.dart` и `screens/*`.

## Где что лежит (бэкенд — `my_serve_chat_test/`)

| Область | Где искать |
|--------|------------|
| Точка входа, middleware | `index.js`, `middleware/auth.js` |
| Маршруты | `routes/` (в т.ч. `routes/chats/`, `routes/messages/`, `routes/students/`, `routes/reports.js`, …) |
| Контроллеры | `controllers/` |
| SQL / репозитории | `repositories/` |
| WebSocket | `websocket/websocket.js` |
| Миграции БД | `migrations/` |
| Проверки после изменений бухгалтерии/отчётов | `npm run smoke:reports:permissions`, `smoke:accounting*`, см. `package.json` scripts |

## Документация в репо

- Корневой **README.md** — запуск клиента/сервера, конфиг, деплой.
- **docs/** — гайды; крупный разбор в **docs/tutorial/** (не грузить целиком в контекст без нужды).

## Правила, которые уже заданы проектом

- Соблюдать **`.cursor/rules/project-workflow.mdc`** (верификация: `flutter analyze` на изменённых Dart-файлах, `node --check` на изменённых JS, smoke для отчётов при правках доступа).
- Доступ к отчётам: автор правит свой отчёт, суперпользователь — любой; остальные — нет. При изменении логики доступа — обновить/прогнать smoke сценарий.

## Как работать с запросами пользователя

1. Сначала определить слой: **только клиент**, **только сервер**, или **оба** (например сообщения, отчёты, шифрование чата).
2. Открыть релевантный `*_service.dart` на клиенте и соответствующий `routes` + `controllers` на сервере.
3. Не предполагать секреты в репо: `.env` не трогать без явной просьбы пользователя.
