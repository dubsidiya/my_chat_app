# Отчёт аудита безопасности

**Дата:** 2025-02-25  
**Проект:** Flutter-чат, Node.js (Express), PostgreSQL, WebSocket, Yandex Cloud, Vercel

---

## 1. Секреты и учётные данные

### Что проверялось
- Наличие паролей/ключей/токенов/DATABASE_URL в коде, конфигах, тестах
- Файлы .env, *.pem, credentials, SSH-ключи в репозитории и .gitignore
- Документация и примеры на реальные секреты
- .env.example без реальных значений
- JWT_SECRET только из окружения, без дефолта в коде
- Вхождения password, secret, token, api_key, DATABASE_URL, Authorization

### Результат: **УЯЗВИМОСТЬ / ПРЕДУПРЕЖДЕНИЕ**

| Проверка | Статус | Файлы/строки |
|----------|--------|--------------|
| Секреты вынесены в .env | ✅ OK | `db.js`, `index.js`, `middleware/auth.js` — используют `process.env` |
| .gitignore покрывает секреты | ✅ OK | `.gitignore`: `.env`, `**/env-yandex-vm.txt`, `scripts/.deploy_key`, `scripts/vm-connection.txt`, `docs/YANDEX_DB_CREDENTIALS.txt` |
| Файлы с реальными секретами в рабочей копии | ⚠️ **УЯЗВИМОСТЬ** | **`my_serve_chat_test/env-yandex-vm.txt`** — содержит реальные `DATABASE_URL`, `JWT_SECRET`, `YANDEX_SECRET_ACCESS_KEY`. **`docs/YANDEX_DB_CREDENTIALS.txt`** — пароль БД и строка подключения в открытом виде. Эти файлы перечислены в .gitignore, но **присутствуют в дереве** и при случайном `git add .` могут попасть в коммит. |
| Документация без реальных секретов | ⚠️ Предупреждение | В `docs/YANDEX_SERVER_MIGRATION.md`, `YANDEX_DB_MIGRATION.md` — только плейсхолдеры и описания. В **YANDEX_DB_CREDENTIALS.txt** — реальный пароль (файл должен быть только локально и не коммититься). |
| .env.example | ✅ OK | `my_serve_chat_test/.env.example` — только примеры (`your-super-secret-...`, `user:password@host`) |
| JWT_SECRET | ✅ OK | `index.js` (39–48): только из `process.env`, в production проверка длины ≥ 32, нет дефолта в коде |
| Утечка в коде | ✅ OK | В коде нет присвоения секретов литералами; пароли только в body запросов и сразу хешируются |

### Рекомендации
1. **Немедленно:** Убедиться, что `my_serve_chat_test/env-yandex-vm.txt`, `my_serve_chat_test/.env`, `docs/YANDEX_DB_CREDENTIALS.txt` **не отслеживаются** git: `git status` не должен показывать их как staged. Если они когда-либо коммитились — **сменить все пароли и JWT_SECRET**, затем удалить файлы из истории (BFG Repo-Cleaner или `git filter-repo`).
2. Хранить env-yandex-vm.txt только на доверенной машине; не класть в облачные папки с общим доступом.
3. В документации не вставлять реальные значения; для примеров использовать `postgresql://user:REDACTED@host/db`.

---

## 2. Бэкенд: аутентификация и авторизация

### Что проверялось
- Хранение паролей (хеш), логирование паролей
- JWT: algorithm, защита от alg:none, лимит длины токена
- Защита эндпоинтов middleware, IDOR по userId/chatId
- Суперпользователь и привилегированные действия
- WebSocket: проверка токена и доступ по chatId

### Результат: **OK**

| Проверка | Статус | Файлы/строки |
|----------|--------|--------------|
| Пароли только хеш | ✅ OK | `authController.js`: bcrypt.hash/bcrypt.compare, пароли не логируются |
| JWT algorithm | ✅ OK | `middleware/auth.js` (31, 58–61): `algorithms: ['HS256']`, `algorithm: 'HS256'` |
| Защита от DoS по длине токена | ✅ OK | `middleware/auth.js` (26–29): `MAX_TOKEN_LENGTH = 4096` |
| Эндпоинты под authenticateToken | ✅ OK | `routes/auth.js`, `chats.js`, `messages.js`, `admin.js`, `reports.js`, `moderation.js`, `setup.js` — защищённые маршруты за `authenticateToken` |
| userId из токена, не из body/params | ✅ OK | `deleteAccount`, `changePassword` (authController 447–450, 554–557): проверка `currentUserId.toString() !== userId.toString()` → 403. В чатах `userId`/`requesterId` из `req.user.userId` |
| Суперпользователь | ✅ OK | `routes/admin.js`: `router.use(authenticateToken, requireSuperuser)`. `adminResetUserPassword` только через этот роут |
| WebSocket токен и комнаты | ✅ OK | `websocket/websocket.js`: токен из header/query, `verifyWebSocketToken`; для каждого действия (subscribe, typing, send, mark_read) — `ensureChatMember(chatId, userId)` с userId из токена |

### Рекомендации
- Нет критичных замечаний.

---

## 3. Бэкенд: ввод и инъекции

### Что проверялось
- Параметризованные запросы к БД
- Валидация и санитизация (типы, границы, null-byte, zero-width)
- Загрузка файлов: MIME, расширение, path traversal, лимиты
- Утечка деталей в ответах (stack, пути, версии)

### Результат: **OK**

| Проверка | Статус | Файлы/строки |
|----------|--------|--------------|
| Параметризованные запросы | ✅ OK | Поиск по `pool.query`: везде используются `$1, $2, ...` и массивы параметров, конкатенации SQL с пользовательским вводом нет |
| Валидация/санитизация | ✅ OK | `utils/validation.js`: логин 4–50 символов, пароль 6–128; `utils/sanitize.js`: `parsePositiveInt`, `sanitizeForDisplay`, `sanitizeMessageContent` (удаление управляющих и zero-width). В чатах `MAX_USER_IDS`, `MAX_ADD_MEMBERS` |
| Загрузка файлов | ✅ OK | `uploadImage.js`: только разрешённые MIME и расширения, **SVG исключён** (комментарий про XSS). `uploadFile.js`: whitelist расширений и MIME, `path.basename` + замена `\0`, лимит 100 MB. Имена в облаке — уникальный суффикс, path traversal исключён |
| Утечка в ответах | ✅ OK | 404/500 в `index.js` (286–294): нейтральные сообщения. В контроллерах клиенту отдаётся только `message: '...'`, stack только в `console.error` на сервере |

### Рекомендации
- В production убедиться, что логи с `error.stack` не попадают в публичные системы (только внутренние логи).

---

## 4. Бэкенд: CORS, заголовки, rate limit

### Что проверялось
- CORS: конфигурация origin, нет * в production
- Заголовки безопасности (X-Frame-Options, X-Content-Type-Options, HSTS, X-Powered-By)
- Rate limit на логин/регистрацию, API, загрузки, чувствительные действия; trust proxy

### Результат: **OK**

| Проверка | Статус | Файлы/строки |
|----------|--------|--------------|
| CORS | ✅ OK | `index.js` (70–185): `ALLOWED_ORIGINS` и `ALLOWED_ORIGIN_PATTERNS` из env, в production предупреждение если не заданы; дефолт — конкретные домены и `https://*.vercel.app`; нет `*` для production |
| Заголовки | ✅ OK | `index.js` (25, 59–67): `x-powered-by` отключён; Helmet + X-Frame-Options DENY, Referrer-Policy, Permissions-Policy; HSTS в production |
| Rate limit | ✅ OK | `index.js`: globalLimiter 600/15min; authLimiter на `/auth/login`, `/auth/register` (5 попыток, skipSuccessfulRequests); apiLimiter на /messages, /chats и др.; uploadLimiter на upload-эндпоинты; в auth.js — sensitiveActionLimiter на delete/changePassword |
| Trust proxy | ✅ OK | `index.js` (52): `app.set('trust proxy', 1)` |

### Рекомендации
- В production обязательно задать `ALLOWED_ORIGINS` (и при необходимости `ALLOWED_ORIGIN_PATTERNS`).

---

## 5. Логирование и PII

### Что проверялось
- В логах не попадают пароли, токены, полные cookie
- При неудачном логине/регистрации не логируются PII в production
- В логах ошибок нет тела запроса и заголовков с токенами

### Результат: **OK**

| Проверка | Статус | Файлы/строки |
|----------|--------|--------------|
| Секреты в логах | ✅ OK | `utils/auditLog.js`: только `event`, `ip`, `userId` (опционально). В authController при login_fail вызывается `securityEvent('login_fail', req)` без username/пароля |
| Логи ошибок | ✅ OK | В коде нет логирования `req.body` или `Authorization` в production; stack только в `console.error` на сервере |

### Рекомендации
- Сохранять практику: в audit/security не добавлять email/логин при login_fail (достаточно ip и userId после успешного входа).

---

## 6. Фронт и клиент

### Что проверялось
- Хранение токена (secure storage, не localStorage при риске XSS)
- Отсутствие хардкода API-ключей; базовый URL из конфига/dart-define
- Сборка без вшитых .env/ключей

### Результат: **OK / ПРЕДУПРЕЖДЕНИЕ**

| Проверка | Статус | Файлы/строки |
|----------|--------|--------------|
| Хранение токена | ⚠️ Предупреждение | `lib/services/storage_service.dart` (37–44): на **web** токен в `SharedPreferences` (localStorage-подобное). На mobile/desktop — `FlutterSecureStorage`. Для веб-сборки при наличии XSS токен может быть доступен скрипту. Риск зависит от контента и CSP. |
| Нет хардкода секретов | ✅ OK | `lib/config/api_config.dart`: базовый URL из `String.fromEnvironment('API_BASE_URL')` с дефолтом `https://reollity.duckdns.org`; это домен, не секрет |
| Сборка | ✅ OK | Нет вшивания .env в артефакты; Vercel — статика Flutter, секреты не нужны на фронте |

### Рекомендации
- Для веб-версии: оценить CSP и минимизацию инъекций; при высоких требованиях рассмотреть httpOnly cookie для сессии вместо токена в localStorage (потребуются изменения на бэкенде).

---

## 7. Инфраструктура и деплой

### Что проверялось
- Скрипты и документация без реальных паролей и приватных ключей
- GitHub Actions: секреты только через secrets, не в логах
- Открытые конфиги без чувствительных данных

### Результат: **OK**

| Проверка | Статус | Файлы/строки |
|----------|--------|--------------|
| Скрипты и доки | ✅ OK | В скриптах и .md — пути к ключам (`scripts/.deploy_key`), IP (93.77.185.6), команды без подстановки паролей. Приватный ключ не в репо (в .gitignore) |
| GitHub Actions | ✅ OK | `.github/workflows/deploy-yandex-vm.yml`: host, username, key из `secrets.DEPLOY_*`; в логах выводятся только "Deploy done.", без секретов |
| Конфиги | ✅ OK | `vercel.json` — только build, rewrites, headers. Workflow — только ссылки на настройку секретов в UI |

### Рекомендации
- Не коммитить `scripts/vm-connection.txt` и не вставлять его содержимое в публичную документацию.

---

## 8. Зависимости

### Что проверялось
- npm audit в каталоге бэкенда
- Известные уязвимые версии ключевых пакетов

### Результат: **ПРОВЕРИТЬ ВРУЧНУЮ**

| Проверка | Статус | Файлы/строки |
|----------|--------|--------------|
| npm audit | ⚠️ Выполнить вручную | В каталоге `my_serve_chat_test` выполнить: `npm audit`. Критические и высокие уязвимости устранить (`npm audit fix` где возможно) или задокументировать обоснование |
| Ключевые пакеты | ✅ По коду | express, jsonwebtoken, pg, bcrypt, multer используются с параметризацией и без опасных паттернов; версии — по package.json |

### Рекомендации
- Регулярно запускать `npm audit` и обновлять зависимости по графику.

---

## 9. Прочее

### Что проверялось
- Опасные вызовы (eval, Function('...'), exec с пользовательским вводом, require по пользовательским данным)
- Чувствительные эндпоинты (сброс пароля, CORS) защищены ролью/суперпользователем
- Ограничения на размер тела, длину строк, размер массивов

### Результат: **OK**

| Проверка | Статус | Файлы/строки |
|----------|--------|--------------|
| eval / exec / require по вводу | ✅ OK | В коде приложения таких вызовов нет (только в node_modules) |
| Защита чувствительных эндпоинтов | ✅ OK | Сброс пароля: `admin.js` → `requireSuperuser`. Настройка CORS: `setup.js` → `authenticateToken`, `requireSuperuser` |
| Лимиты | ✅ OK | `index.js`: body JSON/urlencoded 512kb; в uploadImage 10 MB, в uploadFile 100 MB; в чатах MAX_USER_IDS (50), MAX_ADD_MEMBERS; сообщения в WS до 64 KB; validation — длина логина/пароля |

### Рекомендации
- Нет критичных замечаний.

---

## Сводная таблица

| № | Категория | Вердикт | Критичные действия |
|---|-----------|---------|--------------------|
| 1 | Секреты и учётные данные | ⚠️ Уязвимость/предупреждение | Убедиться, что env-yandex-vm.txt и YANDEX_DB_CREDENTIALS.txt не в git; при наличии в истории — ротация секретов и очистка истории |
| 2 | Бэкенд: аутентификация и авторизация | ✅ OK | — |
| 3 | Бэкенд: ввод и инъекции | ✅ OK | — |
| 4 | CORS, заголовки, rate limit | ✅ OK | Задать ALLOWED_ORIGINS в production |
| 5 | Логирование и PII | ✅ OK | — |
| 6 | Фронт и клиент | ✅ OK / предупреждение | Учёт риска XSS для токена на web (SharedPreferences) |
| 7 | Инфраструктура и деплой | ✅ OK | — |
| 8 | Зависимости | ⚠️ Проверяется в CI | npm audit выполняется в GitHub Actions (Security check) |
| 9 | Прочее | ✅ OK | — |

---

## Приоритизированный список действий

1. **Критично:** Проверить, что файлы с реальными секретами не отслеживаются git и не попадали в историю. Если попадали — сменить все пароли (БД, Yandex), JWT_SECRET и при необходимости ключи; удалить файлы из истории репозитория.
2. **Критично:** Удалить или перенести реальные секреты из `my_serve_chat_test/env-yandex-vm.txt` и `docs/YANDEX_DB_CREDENTIALS.txt` из рабочей копии в безопасное место (например только на ВМ и в менеджере секретов), не держать копии с паролями в репо.
3. **Высокий:** В каталоге `my_serve_chat_test` выполнить `npm audit` и устранить критические/высокие уязвимости (или задокументировать обоснование).
4. **Средний:** В production явно задать `ALLOWED_ORIGINS` (и при необходимости `ALLOWED_ORIGIN_PATTERNS`) в .env на ВМ.
5. **Низкий:** Для веб-сборки Flutter оценить риск XSS и при необходимости рассмотреть альтернативы хранению токена (например httpOnly cookie).

---

## Исправления по результатам аудита (применено)

- **.gitignore:** добавлены `*.pem`, разрешены примеры без секретов: `!**/env-yandex-vm.example.txt`, `!docs/YANDEX_DB_CREDENTIALS.example.txt`.
- **Примеры секретов:** созданы `my_serve_chat_test/env-yandex-vm.example.txt`, `docs/YANDEX_DB_CREDENTIALS.example.txt` (только плейсхолдеры).
- **Production CORS:** в `my_serve_chat_test/index.js` при `NODE_ENV=production` сервер не запускается без заданного `ALLOWED_ORIGINS` (process.exit(1)).
- **Документация:** добавлены `docs/SECRETS_ROTATION.md` (ротация секретов, удаление из истории), скрипт `scripts/check-no-secrets-staged.sh` для проверки перед коммитом.
- **Фронт:** в `lib/services/storage_service.dart` добавлен комментарий о риске XSS при хранении токена в SharedPreferences на web.
- **CI:** добавлены `scripts/ci-check-no-secrets.sh` и workflow `.github/workflows/security-check.yml`. При каждом **push** и **pull_request** автоматически: проверка, что файлы с секретами не отслеживаются в репо; `npm ci` и `npm audit --audit-level=high` в бэкенде (при высоких/критических уязвимостях сборка падает).

Ничего запускать вручную не нужно: проверки выполняются в GitHub Actions.

---

*Отчёт сформирован по чек-листу из docs/SECURITY_AUDIT_PROMPT.md.*
