# Logic Audit — my_chat_app (reollity)

**Дата:** 2026-06-02  
**Rev. 2:** исключён модуль «E2EE» — см. раздел ниже  
**Тип:** полный аудит бизнес-логики (не security)  
**Стек:** Flutter (`lib/`) + Node/Express/PostgreSQL/WebSocket (`my_serve_chat_test/`)

---

## Шифрование сообщений — не E2EE (вне scope аудита)

Перепроверка кода показала: **настоящего end-to-end шифрования нет**. Клиент шифрует текст перед отправкой, но **симметрический ключ чата хранится на сервере в открытом виде** и выдаётся любому участнику по API.

| Факт | Где в коде |
|------|------------|
| При создании чата сервер **генерирует** AES-ключ | `chatsController.js:532-541` — `crypto.randomBytes(32).toString('base64')` → `chats.shared_chat_key` |
| Ключ лежит в БД plaintext (base64) | миграция `add_chat_shared_key.sql`: «сервер хранит один общий AES-256 ключ (base64) на чат» |
| Участник получает ключ **как есть** | `GET /e2ee/chat/:chatId/shared-key` → `{ chatKey }` (`e2eeController.js:346-376`) |
| Клиент **сначала** берёт shared-key с сервера | `e2ee_service.dart:205-208` — `_fetchSharedChatKey` до legacy-пути X25519/`chat_keys` |

**Вывод:** это шифрование «от посторонних глаз в БД без ключа», но **не** модель «сервер не может прочитать». Админ БД / компрометация сервера = доступ ко всем сообщениям. Старый путь (`chat_keys` с обёрткой через X25519) остаётся fallback для старых чатов; **новые чаты** — упрощённая серверная модель.

Документы `E2EE_SYSTEM_GUIDE.md` и `E2EE_METADATA_THREAT_MODEL.md` описывают в основном legacy-модель и **не отражают** текущий `shared_chat_key`.

**Findings по E2EE, кэшу ciphertext, key_version, gallery decrypt — сняты с рассмотрения** (LOGIC-004, 005, 012, 019, 022). Их «исправление» не даёт реальной приватности при server-held key.

---

## Карта модулей и задуманное поведение

| # | Модуль | Задумано (из кода/docs) | Ключевые файлы |
|---|--------|-------------------------|----------------|
| 1 | Auth / сессия | JWT + refresh; роли из env (`SUPERUSER_*`, `PRIVATE_ACCESS_*`); logout чистит кэш | `auth_service.dart`, `middleware/auth.js` |
| 2 | Чаты | Личные/групповые; участник видит только свои чаты; admin/owner управляет группой | `chats_service.dart`, `chatsController.js` |
| 3 | Сообщения / WS | HTTP send + idempotency; WS для live; Hive-кэш | `messages_service.dart`, `websocket.js`, `local_messages_service.dart` |
| 4 | ~~E2EE / медиа~~ | **Out of scope** — server-held key, см. выше | — |
| 5 | Push | FCM после login; suppress если чат открыт | `push_notification_service.dart` |
| 6 | Ученики / занятия | Препод видит своих; super — всех; makeup-debt badges; депозиты — super only | `students_service.dart`, `studentsController.js` |
| 7 | Отчёты | Owner edit own / super edit any / foreign → 404; max **4** ученика/slot (**ASSUMPTION:** в QA-матрице указано 2) | `reportsController.js`, `report_builder_screen.dart` |
| 8 | Модерация | Block скрывает сообщения заблокированного | `moderationController.js`, REST filters |
| 9 | Сквозные | Retry/snackbar при сети; refresh списков после pop | экраны + сервисы |
| 10 | Модели | snake_case с сервера → Dart models | `lib/models/` |

---

## A. Executive summary

Логика приложения в целом зрелая: серверные инварианты (IDOR на чатах/сообщениях, права на отчёты, idempotency отправки) реализованы последовательно, smoke-тесты бухгалтерии проходят. Основные проблемы — **расхождения клиент ↔ сервер** и **неполная реализация UX-обещаний**, а не дыры в backend-авторизации.

**Топ-3 риска для пользователей** (без учёта «E2EE»):

1. **Superuser без `PRIVATE_ACCESS_*`** — API пускает в бухгалтерию, UI блокирует вход в «Учёт занятий» / «Отчёты».
2. **Блокировка пользователя** — REST фильтрует сообщения, WebSocket доставляет их live; `getBlockedUserIds()` на клиенте не вызывается.
3. **Кэш сообщений Hive** — replace одной страницей и race при concurrent write → потеря истории offline (LOGIC-002/003).

Backend отчётов и smoke permissions — **OK** (superuser-сценарии в smoke пропущены из‑за env, не из‑за падения).

---

## B. Матрица модулей

| Модуль | Статус | OK / Warning / Bug | Кратко |
|--------|--------|-------------------|--------|
| 1 Auth / сессия | Warning | 2 Bug, 4 Warning | Super-only UI; stale роли после refresh; нет global 401-retry |
| 2 Чаты / участники | Warning | OK + 2 Warning | Server OK; group admin UI не по ролям |
| 3 Сообщения / WS | Warning | 2 Bug, 4 Warning | Кэш Hive, unread, read receipts |
| 4 ~~E2EE~~ | N/A | — | Server-held key; не audit scope |
| 5 Push | OK | 2 Warning | Работает; iOS token с задержкой |
| 6 Ученики / занятия | Warning | 1 Bug, 2 Warning | Makeup summary не для super; balance=0 после create |
| 7 Отчёты | OK | 2 Warning, 1 Info | Права на сервере OK; reminder TZ; нет confirm ≥10000₽ |
| 8 Модерация | Bug | 1 Bug, 1 Warning | Block не на WS; dead client sync |
| 9 Сквозные | Warning | Warning | Poll не пишет в кэш; race cache write |
| 10 Модели / API | Warning | 1 Bug, 1 Warning | `target_teacher_id` не парсится |

---

## C. Findings

### Critical / High

#### LOGIC-001 · High · Auth

- **Ожидалось:** Superuser проходит в private-секции (сервер: `privateAccess || isSuperuser`).
- **Фактически:** `_ensurePrivateAccess()` проверяет только `privateAccess`.
- **Где:** `lib/screens/home_screen.dart:1547-1549` vs `my_serve_chat_test/middleware/auth.js:118-125`
- **Воспроизведение:** Super в `SUPERUSER_*`, не в `PRIVATE_ACCESS_*` → snackbar, нет входа в «Отчёты».
- **Рекомендация:** `allowed = privateAccess || isSuperuser` (из `fetchMe()` или `widget.isSuperuser`).
- **Нужен smoke/UI:** да (UI)

#### LOGIC-002 · High · Messages / cache

- **Ожидалось:** Кэш накапливает историю.
- **Фактически:** `saveMessages()` полностью заменяет ключ `chat_$chatId` текущей страницей (50 msg).
- **Где:** `lib/services/local_messages_service.dart:23-30`, `lib/services/messages_service.dart:116-119`
- **Рекомендация:** merge по id, не replace.
- **Нужен smoke/UI:** да (offline)

#### LOGIC-003 · High · Messages / cache

- **Ожидалось:** Concurrent send + fetch не теряют данные.
- **Фактически:** `Future.delayed(100ms)` + `saveMessages` может перезаписать более свежий `addMessage`.
- **Где:** `lib/services/messages_service.dart:116-119`
- **Рекомендация:** merge или отмена stale write.
- **Нужен smoke/UI:** да

#### LOGIC-006 · High · Moderation

- **Ожидалось:** Заблокированный не виден в чате.
- **Фактически:** REST фильтрует `user_blocks`; WS broadcast без фильтра.
- **Где:** `my_serve_chat_test/controllers/messagesController.js:207`; `my_serve_chat_test/websocket/` — нет `user_blocks`
- **Рекомендация:** Фильтр при WS broadcast или client-side filter через `getBlockedUserIds()`.
- **Нужен smoke/UI:** да

#### LOGIC-007 · High · Students

- **Ожидалось:** Super видит makeup-debt по всем ученикам (как полный список).
- **Фактически:** `getAllStudents` — все; `getMakeupPendingSummary` — только `teacher_id = current`.
- **Где:** `my_serve_chat_test/controllers/studentsController.js:46-58` vs `91-114`
- **Рекомендация:** Super branch в makeup summary (global или per-teacher).
- **Нужен smoke/UI:** да

---

### Medium

#### LOGIC-008 · Medium · Auth

- **Ожидалось:** Refresh обновляет `isSuperuser` / `privateAccess`.
- **Фактически:** Сервер отдаёт поля (`authController.js:442-443`); клиент берёт старые из storage (`auth_service.dart:380-387`).
- **Рекомендация:** Парсить refresh response и обновлять flags.

#### LOGIC-009 · Medium · Auth

- **Ожидалось:** Авто-refresh при 401 mid-session.
- **Фактически:** Только при старте в `hasValidSession()`; `HttpService` без interceptor.
- **Где:** `lib/services/http_service.dart`, `lib/services/auth_service.dart:343-355`

#### LOGIC-010 · Medium · Messages / unread

- **Ожидалось:** Нет unread в открытом чате.
- **Фактически:** Home WS increment без проверки `PushNotificationService.currentChatId`.
- **Где:** `lib/screens/home_screen.dart:563-597`

#### LOGIC-011 · Medium · Messages / read

- **Ожидалось:** Новые msg в открытом чате → read.
- **Фактически:** `markChatAsRead()` один раз при init; `markMessageAsRead` не вызывается из UI.
- **Где:** `lib/screens/chat_screen.dart:582-585`

#### LOGIC-013 · Medium · Chats / UI

- **Ожидалось:** Add/rename/clear — только owner/admin.
- **Фактически:** UI для всех участников группы; server 403.
- **Где:** `lib/screens/chat_screen.dart:928-1017`

#### LOGIC-014 · Medium · WS (latent)

- **Ожидалось:** Единый send pipeline (idempotency, push, membership).
- **Фактически:** WS `type: 'send'` вставляет plain text напрямую; Flutter не использует, но custom client может.
- **Где:** `my_serve_chat_test/websocket/websocket.js:382-433`

#### LOGIC-015 · Medium · Reports

- **Ожидалось:** Confirm price ≥ 10000₽ (как в `add_lesson_screen`).
- **Фактически:** Только ±35% ratio dialog; server принимает любой `price > 0`.
- **Где:** `lib/screens/add_lesson_screen.dart:32-33`; `lib/screens/report_builder_screen.dart` — нет 10000

#### LOGIC-016 · Medium · Reports

- **Ожидалось:** «Вчера» = timezone преподавателя (как `is_late`).
- **Фактически:** `DateTime.now()` устройства.
- **Где:** `lib/screens/reports_chat_screen.dart:64-81`

#### LOGIC-017 · Medium · Students

- **Ожидалось:** Balance сразу после create/link.
- **Фактически:** Server без `balance`; client `?? 0.0`.
- **Где:** `lib/services/students_service.dart:156-158`

#### LOGIC-018 · Medium · Models

- **Ожидалось:** `target_teacher_id` в депозитах.
- **Фактически:** API возвращает; `Transaction.fromJson` не парсит.
- **Где:** `lib/models/transaction.dart:73-88`

#### LOGIC-020 · Medium · Moderation

- **Ожидалось:** Sync blocked IDs на клиенте.
- **Фактически:** `getBlockedUserIds()` нигде не вызывается.
- **Где:** `lib/services/moderation_service.dart:40-50`

---

### Low / Info

#### LOGIC-021 · Low · Reports / audit

Server `message` при missing table не показывается в UI (`lib/services/reports_service.dart:273-274`).

#### LOGIC-023 · Low · Misleading query params

`?userId=` на delete (server игнорирует).

#### LOGIC-024 · Low · Push

FCM token на iOS после `MainTabsScreen`, не сразу после login.

#### LOGIC-025 · Info · Spec mismatch

Max **4** students/slot (не 2): `my_serve_chat_test/services/reports/reportHelpers.js:4`.

#### LOGIC-026 · Info · Reports access

Foreign edit → **404** (by design, smoke OK).

#### LOGIC-027 · Low · Poll fallback

Не обновляет Hive (`lib/screens/chat_screen.dart:597-625`).

#### LOGIC-028 · Low · Auth

Invalid JWT → 403 вместо 401 (`my_serve_chat_test/middleware/auth.js:77-81`).

---

### Снято с рассмотрения (Rev. 2 — server-held key, не E2EE)

| ID | Было | Причина снятия |
|----|------|----------------|
| LOGIC-004 | Dedup temp/WS при E2EE | Слой шифрования не даёт реальной E2EE; UX-bubble — низкий приоритет |
| LOGIC-005 | Cache без decrypt | Привязано к ciphertext; не приоритет без настоящего E2EE |
| LOGIC-012 | Ciphertext в preview чата | То же |
| LOGIC-019 | `key_version` в gallery | То же |
| LOGIC-022 | Dead `GET /e2ee/public-key/:userId` | Модуль e2ee вне scope |

---

### Что согласовано (без findings)

- Report ownership на сервере + smoke owner/foreign contract
- Chat/message IDOR на HTTP (membership checks)
- HTTP send idempotency (`Idempotency-Key`)
- Pagination `before` + `limit` client ↔ server
- WS reconnect resync policy (unit tests `chat_sync_policy_test.dart`)
- Draft reports autosave/restore
- Deposits super-only (routes + UI gate)

---

## D. Пробелы в тестах

**Не покрыто smoke / unit:**

- Superuser private UI gate (LOGIC-001)
- Hive merge/replace и cache race (LOGIC-002/003)
- Block filter on WS (LOGIC-006)
- Super makeup summary scope (LOGIC-007)
- Refresh updates role flags (LOGIC-008)
- Unread suppression when chat open (LOGIC-010)

**Приоритетные smoke (3–5):**

1. `smoke-super-private-ui.js` — super без private: GET `/reports` 200, документировать expected UI (HTTP only).
2. `smoke-makeup-summary-super.js` — super GET `/students/makeup-pending` vs count students with debt globally.
3. `smoke-ws-block-filter.js` — block user A→B; WS message from A not delivered to B's socket.
4. `smoke-reports-permissions.js` — **добавить** super update foreign (с env `SUPERUSER_*`).
5. `smoke-report-price-threshold.js` — optional: document no server rule for 10000 (client-only gap).

`flutter test` — 97 тестов, в основном models/widgets; **нет** integration auth/cache/moderation.

---

## E. Ручной чеклист UI

| ID | Шаги | Ожидаемый результат |
|----|------|---------------------|
| UI-01 | Super без private → «Отчёты» | Доступ открыт (сейчас snackbar — баг LOGIC-001) |
| UI-02 | Чат → offline → reopen | История сохранена (сейчас может обрезаться — LOGIC-002) |
| UI-03 | Открытый чат → входящее msg | Unread не растёт на home (LOGIC-010) |
| UI-04 | Block user → новое msg в чате | Не появляется (сейчас WS — LOGIC-006) |
| UI-05 | Report builder price 15000 | Confirm dialog (урок — есть; отчёт — нет) |
| UI-06 | Reminder «вчера» при TZ ≠ device | Совпадает с server report_date |
| UI-07 | Super → makeup badges на чужих учениках | Корректные счётчики |
| UI-08 | Group member (не admin) → «Добавить участника» | 403 snackbar |
| UI-09 | Create student → сразу balance | Реальный balance после refresh |

---

## F. Что проверено автоматически

| Команда | Результат |
|---------|-----------|
| `flutter analyze` | **exit 1** — 47× info (curly_braces, prefer_const); **0 errors** |
| `flutter test` | **exit 0** — All tests passed! (97 tests) |
| `node --check` routes/controllers/websocket/middleware | **exit 0** — без ошибок |
| `npm run smoke:reports:permissions` | **exit 0** — ok (super update **пропущен**, нет super в env) |
| `npm run smoke:accounting` | **exit 0** — ok |
| `npm run smoke:accounting:edge` | **exit 0** — ok (super delete lesson **пропущен**) |

---

## Связанные документы

- `docs/SECURITY_AUDIT_PROMPT.md` — отдельный security-аудит
- `docs/QA_FUNCTIONAL_MATRIX_LESSONS_REPORTS.md` — матрица ручного прогона занятий/отчётов
- `.cursor/prompts/smoke-test-generation.md` — формат smoke-тестов
- `my_serve_chat_test/migrations/add_chat_shared_key.sql` — фактическая модель «ключа на сервере»
