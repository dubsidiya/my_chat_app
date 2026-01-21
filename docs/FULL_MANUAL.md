# Полный мануал по проекту `my_chat_app`

Этот документ — “книга” по тому, **как работает приложение**: Flutter‑клиент + Node.js/Express backend + PostgreSQL + WebSocket.

> Важно: полный построчный разбор *всего* репозитория — очень объёмная работа. Этот мануал написан так, чтобы его можно было дополнять главами (по файлам/модулям) без потери целостности.

---

## Оглавление

1. **Общая картина системы**
2. **Состав репозитория**
3. **Данные и база (PostgreSQL)**
4. **Backend (Node.js/Express): ключевые потоки**
5. **WebSocket: протокол и события**
6. **Flutter: ключевые экраны и потоки**
7. **Кэш сообщений (локально)**
8. **Деплой и окружения (Render)**
9. **Appendix A — Построчный разбор `my_serve_chat_test/index.js`**
10. **Appendix B — Построчный разбор `lib/main.dart`**

---

## 1) Общая картина системы

### 1.1 Компоненты

- **Flutter приложение** (`lib/…`): UI, авторизация, список чатов, экран чата, кэш сообщений, работа с REST и WebSocket.
- **Backend** (`my_serve_chat_test/…`): REST API (auth/chats/messages/…), WebSocket сервер, интеграция с PostgreSQL, загрузка изображений в Object Storage.
- **PostgreSQL**: хранит пользователей, чаты, сообщения, статусы прочтения, реакции, закрепления, сущности “студенты/занятия/отчёты”.

### 1.2 Как обычно происходит работа пользователя (высокоуровнево)

1) Пользователь входит (логин/пароль) → получает **JWT**.  
2) Flutter сохраняет токен и подставляет в `Authorization: Bearer …` в запросы.  
3) Flutter загружает список чатов (теперь через `GET /chats`), показывает last message и unread.  
4) При открытии чата Flutter:
   - загружает сообщения (`GET /messages/:chatId` с пагинацией),
   - подключается к WebSocket `wss://…?token=JWT`,
   - отмечает сообщения как прочитанные (`POST /messages/chat/:chatId/read-all`).
5) При отправке сообщения:
   - REST `POST /messages` сохраняет в БД и рассылает событие через WebSocket участникам.

---

## 2) Состав репозитория (кратко)

- `lib/` — Flutter код (экраны, сервисы API, модели).
- `my_serve_chat_test/` — Node.js сервер (routes/controllers/middleware).
- `docs/` — документация, гайды, SQL‑скрипты/миграции.
- `android/ ios/ macos/ windows/ linux/ web/` — платформенные части Flutter.

---

## 3) Данные и база (PostgreSQL)

Основные таблицы (упрощённо):
- `users` — пользователи (логин хранится в `email`).
- `chats` — чаты (`created_by`, `is_group`).
- `chat_users` — связи пользователь ↔ чат.
- `messages` — сообщения (текст/изображения/ответы/статусы).
- `message_reads` — прочтения сообщений (для unread).
- `pinned_messages` — закрепления.
- `message_reactions` — реакции.

Плюс “репетиторский блок”:
- `students`, `lessons`, `transactions`, `reports`, `report_lessons`.

---

## 4) Backend (Node.js/Express): ключевые потоки

### 4.1 Аутентификация

- При логине/регистрации сервер выдаёт JWT.
- `authenticateToken` валидирует JWT и кладёт `req.user`/`req.userId`.
- Некоторые разделы требуют `privateAccess` (доп. токен через приватный код).

### 4.2 Чаты

- `GET /chats` — список чатов с последним сообщением и количеством непрочитанных.
- `GET /chats/:id` — legacy endpoint (исторически “список чатов пользователя”).
- `POST /chats` — создать чат.
- `GET /chats/:id/members` — участники (только если вы участник).
- `POST/DELETE /chats/:id/members` — управление участниками (ограничено создателем).

### 4.3 Сообщения

- `GET /messages/:chatId` — сообщения + пагинация + read/reply/reactions/pins.
- `POST /messages` — отправка/пересылка.
- `GET /messages/chat/:chatId/search?q=…` — поиск в чате.
- `GET /messages/chat/:chatId/around/:messageId` — “прыжок” к сообщению (контекст вокруг).

---

## 5) WebSocket: протокол и события

Подключение: `wss://my-server-chat.onrender.com?token=<JWT>`

События (примеры):
- сообщение (без `type`, либо с полями сообщения),
- `message_deleted`,
- `message_edited`,
- `message_read`,
- `messages_read`,
- `reaction_added`,
- `reaction_removed`.

---

## 6) Flutter: ключевые экраны и потоки

- `LoginScreen` / `RegisterScreen` — вход/регистрация
- `MainTabsScreen` — основной контейнер (табы)
- `HomeScreen` — список чатов (last message + unread)
- `ChatScreen` — сообщения + WebSocket + реакции/пины/ответы + поиск

---

## 7) Кэш сообщений (локально)

`LocalMessagesService` хранит сообщения локально, чтобы:
- быстро показывать историю,
- позволять офлайн просмотр,
- аккуратно синхронизироваться при появлении сети.

---

## 8) Деплой и окружения (Render)

Backend запускается на Render как Web Service. Важно:
- `JWT_SECRET` — обязателен (особенно для production).
- `DATABASE_URL` — обязателен.
- ключи Object Storage (YANDEX_*) — если нужны изображения.

---

## Appendix A — Построчный разбор `my_serve_chat_test/index.js`

Ниже — объяснение **каждой строки** файла `my_serve_chat_test/index.js` (по состоянию репозитория на момент написания).

> Формат: `L<номер>` → что делает строка.

### Импорты и конфигурация

- **L1**: импорт `express` — основной HTTP framework.
- **L2**: импорт `cors` — middleware для CORS.
- **L3**: импорт `body-parser` — парсинг JSON/форм‑данных.
- **L4**: импорт `dotenv` — чтение `.env` в `process.env`.
- **L5**: импорт `http` — создание HTTP сервера под WebSocket.
- **L6**: импорт `express-rate-limit` — лимитер запросов.
- **L7**: импорт `path` — утилиты путей.
- **L8**: импорт `fileURLToPath` — утилита ESM (URL → path).
- **L10**: подключение роутов auth (`/auth`).
- **L11**: подключение роутов chats (`/chats`).
- **L12**: подключение роутов messages (`/messages`).
- **L13**: подключение роутов students (`/students`) — приватный блок.
- **L14**: подключение роутов reports (`/reports`) — приватный блок.
- **L15**: подключение роутов bankStatement (`/bank-statement`) — приватный блок.
- **L16**: подключение роутов setup (`/setup`) — служебные/настройки.
- **L17**: импорт `setupWebSocket` — инициализация WS сервера.

### Инициализация приложения

- **L19**: `dotenv.config()` — загружает переменные окружения из `.env` (если файл есть).
- **L21**: создаёт `app = express()` — экземпляр Express.
- **L22**: создаёт `server = http.createServer(app)` — HTTP сервер, к которому “прицепится” WS.

### Проверка JWT_SECRET

- **L24**: комментарий — правило для production.
- **L25**: проверка “production и нет JWT_SECRET”.
- **L26**: лог ошибки — почему нельзя стартовать.
- **L27**: `process.exit(1)` — прекращает запуск, чтобы не было небезопасной конфигурации.

### trust proxy

- **L30**: комментарий — зачем trust proxy.
- **L32**: `app.set('trust proxy', true)` — корректно определяет `req.ip` за прокси.

### Security headers

- **L34**: комментарий.
- **L35**: middleware, который добавляет HTTP заголовки.
- **L36**: `X-Content-Type-Options: nosniff` — защита от MIME sniffing.
- **L37**: `X-Frame-Options: DENY` — запрет встраивания в iframe (clickjacking).
- **L38**: `Referrer-Policy: no-referrer` — не отправлять referrer.
- **L39**: `Permissions-Policy: ...` — запрещает гео/микрофон/камеру по умолчанию.
- **L40**: `next()` — передаёт управление следующему middleware.

### CORS

- **L43**: комментарий.
- **L44**: берёт `ALLOWED_ORIGINS` из env или дефолтный список.
- **L45**: парсит CSV строку доменов в массив.
- **L48**: список доменов для разработки.
- **L57**: объединяет списки и убирает дубликаты через `Set`.
- **L59**: подключает `cors()` middleware.
- **L60**: функция проверки origin.
- **L61**: комментарий.
- **L62**: если `origin` отсутствует (часто у мобильных приложений)…
- **L63–L65**: в dev печатает лог.
- **L66**: разрешает запрос.
- **L69**: точное совпадение с allowlist.
- **L70–L74**: разрешает и (в dev) логирует.
- **L77–L83**: отдельное разрешение localhost/127.0.0.1.
- **L85–L91**: разрешение любых поддоменов `.vercel.app` (preview deployments).
- **L93–L99**: разрешение `.netlify.app` (если используется).
- **L101–L104**: в dev печатает блокировку и список разрешённых.
- **L105**: блокирует origin.
- **L107**: `credentials: true` — разрешает cookies/авторизацию (если нужно).
- **L108**: методы.
- **L109**: заголовки.

### Парсинг тела запросов

- **L112**: JSON parser.
- **L113**: urlencoded parser.

### Статика (закомментировано)

- **L115–L119**: было для локальной раздачи изображений; сейчас закомментировано.

### Rate limiting (login/register)

- **L121**: комментарий.
- **L122**: создаёт `authLimiter`.
- **L123**: окно 15 минут.
- **L124**: максимум 5 попыток.
- **L125**: сообщение об ошибке.
- **L126–L127**: стандартные заголовки лимитера.
- **L128**: комментарий.
- **L129–L131**: keyGenerator по `req.ip`.
- **L135**: применяет лимитер к `POST /auth/login`.
- **L136**: применяет лимитер к `POST /auth/register`.

### Подключение роутов

- **L138**: монтирует `authRoutes` на `/auth`.
- **L139**: монтирует `chatRoutes` на `/chats`.
- **L140**: монтирует `messageRoutes` на `/messages`.
- **L141**: монтирует `studentsRoutes`.
- **L142**: монтирует `reportsRoutes`.
- **L143**: монтирует `bankStatementRoutes`.
- **L144**: монтирует `setupRoutes`.

### WebSocket

- **L146**: комментарий.
- **L147**: запускает WebSocket сервер поверх `server`.

### Старт сервера

- **L149**: порт из env или 3000.
- **L151**: обработчик ошибок сервера.
- **L152**: событие `error` на сервере.
- **L153**: логирует ошибку.
- **L154–L156**: спец‑лог если порт занят.
- **L159**: `server.listen`.
- **L160**: лог запуска.
- **L161**: лог окружения.
- **L162**: лог “JWT_SECRET установлен?” (без вывода значения).
- **L163**: лог ALLOWED_ORIGINS.
- **L164**: лог DATABASE_URL установлен?

### Автоконфиг CORS для Object Storage

- **L166**: комментарий.
- **L167–L169**: проверяет наличие YANDEX_* переменных.
- **L170**: если есть конфиг…
- **L171**: лог “настроен”.
- **L173–L188**: если AUTO_SETUP_CORS не false — пробует автоматически настроить CORS для бакета через `setupCors()`.
- **L189–L193**: иначе логирует что Object Storage не настроен.

### Глобальные обработчики ошибок процесса

- **L196**: комментарий.
- **L197–L199**: unhandledRejection логирует промис и причину.
- **L201–L204**: uncaughtException логирует и завершает процесс.

---

## Appendix B — Построчный разбор `lib/main.dart`

Ниже — объяснение **каждой строки** файла `lib/main.dart`.

### Импорты

- **L1**: `material.dart` — Material UI.
- **L2**: `foundation.dart` — `kDebugMode`.
- **L3**: `dart:async` — `runZonedGuarded`.
- **L4**: импорт `LoginScreen` (экран входа).
- **L5**: импорт `MainTabsScreen` (главный экран с табами).
- **L6**: импорт `StorageService` (сохранение токена/пользователя/темы).
- **L7**: импорт `LocalMessagesService` (локальный кэш сообщений).

### main()

- **L9**: объявление `main()`.
- **L10**: комментарий.
- **L11**: переопределяет глобальный обработчик ошибок Flutter.
- **L12**: выводит стандартную ошибку Flutter.
- **L13**: если debug…
- **L14**: печатает exception.
- **L15**: печатает stack trace.
- **L17**: закрывает обработчик.
- **L19**: комментарий.
- **L20**: `runZonedGuarded` — ловит асинхронные ошибки в зоне.
- **L21**: комментарий.
- **L22**: `WidgetsFlutterBinding.ensureInitialized()` — нужно для async init до `runApp`.
- **L23**: инициализация локального хранилища сообщений.
- **L24**: запуск приложения `runApp(MyApp())`.
- **L25**: обработчик ошибок зоны.
- **L26**: если debug…
- **L27**: печатает ошибку.
- **L28**: печатает stack.
- **L30**: закрывает runZonedGuarded.
- **L31**: закрывает `main`.

### MyApp: StatefulWidget

- **L33**: объявляет `MyApp` как StatefulWidget (нужно для смены темы).
- **L34–L35**: связывает состояние `_MyAppState`.
- **L38**: начало `_MyAppState`.
- **L39**: флаг `_isDarkMode`.
- **L40**: статическая ссылка на текущий инстанс state (чтобы менять тему из любого места).
- **L42–L47**: `initState`: сохраняет `_instance`, грузит тему из `StorageService`.
- **L49–L53**: `dispose`: чистит `_instance`.
- **L55–L62**: `_loadThemePreference`: читает сохранённую тему и вызывает `setState`.
- **L64–L71**: `toggleTheme`: обновляет state и сохраняет в `StorageService`.
- **L73–L76**: `updateTheme`: статический доступ к смене темы.

### build(): MaterialApp + автологин

- **L78–L79**: `build`.
- **L80**: `MaterialApp`.
- **L81**: title.
- **L82–L141**: `theme` (светлая тема).
- **L142–L203**: `darkTheme` (тёмная тема).
- **L204**: `themeMode` зависит от `_isDarkMode`.
- **L205**: `home: FutureBuilder` — ждёт `StorageService.getUserData()` (сохранённый пользователь/токен).
- **L209–L242**: пока ждём — показываем экран загрузки.
- **L244**: если есть данные и есть токен…
- **L246–L250**: берёт userId/username и логирует (сейчас в коде есть подробные print).
- **L251–L255**: открывает `MainTabsScreen`, передаёт userId, userEmail и callback смены темы.
- **L256–L266**: иначе печатает, почему автологин не выполнен.
- **L268–L269**: если данных нет — `LoginScreen`.
- **L271–L274**: закрытие `MaterialApp` и `build`.

---

## Дальше (следующие главы мануала)

Следующие построчные главы (буду добавлять далее):
- `my_serve_chat_test/middleware/auth.js`
- `my_serve_chat_test/routes/*.js`
- `my_serve_chat_test/controllers/*Controller.js` (по модулям)
- `my_serve_chat_test/websocket/websocket.js`
- Flutter: `lib/screens/home_screen.dart`, `lib/screens/chat_screen.dart`, `lib/services/*`, `lib/models/*`

---

## Appendix C — Построчный разбор `my_serve_chat_test/middleware/auth.js`

Ниже — объяснение **каждой строки** файла `my_serve_chat_test/middleware/auth.js`.

> Этот файл отвечает за JWT-аутентификацию (middleware), генерацию токена и проверку токена для WebSocket.

### Импорт и конфигурация

- **L1**: импорт `jsonwebtoken` как `jwt` — библиотека для подписи/проверки JWT.
- **L2**: пустая строка для читаемости.
- **L3**: `JWT_SECRET` берётся из `process.env.JWT_SECRET` — секрет подписи токена (обязателен).
- **L4**: пустая строка.

### authenticateToken (middleware)

- **L5**: комментарий — это middleware проверки JWT.
- **L6**: экспорт функции `authenticateToken(req, res, next)`.
- **L7**: проверка: если `JWT_SECRET` не задан…
- **L8**: комментарий — нельзя безопасно проверять токены без секрета.
- **L9**: возвращает HTTP 500 с сообщением о конфигурации сервера.
- **L10**: закрывает `if`.
- **L11**: пустая строка.
- **L12**: читает заголовок `Authorization` из запроса.
- **L13**: достаёт сам токен из формата `Bearer <TOKEN>` (вторая часть после пробела).
- **L14**: пустая строка.
- **L15**: если окружение `development`…
- **L16**: логирует метод и путь запроса (для диагностики).
- **L17**: логирует, есть ли заголовок Authorization.
- **L18**: закрывает `if`.
- **L19**: пустая строка.
- **L20**: если токена нет…
- **L21**: в dev пишет лог.
- **L22**: текст лога.
- **L23**: закрывает `if`.
- **L24**: возвращает HTTP 401 (нет токена).
- **L25**: закрывает `if`.
- **L26**: пустая строка.
- **L27**: `jwt.verify(token, JWT_SECRET, callback)` — проверка подписи/валидности токена.
- **L28**: если `err` (проверка не прошла)…
- **L29**: в dev логирует сообщение ошибки.
- **L30**: строка лога.
- **L31**: закрывает `if`.
- **L32**: возвращает HTTP 403 (токен есть, но невалиден).
- **L33**: закрывает `if (err)`.
- **L34**: пустая строка.
- **L35**: кладёт payload токена в `req.user` (данные пользователя для следующих хендлеров).
- **L36**: дублирует `userId` в `req.userId` для удобства (многие контроллеры читают `req.user.userId`).
- **L37**: комментарий — про совместимость старых токенов.
- **L38**: нормализует флаг `privateAccess` как строго boolean.
- **L39**: комментарий — “email” в payload фактически хранит логин (для обратной совместимости).
- **L40**: в dev включается лог.
- **L41**: лог “JWT verified” + userId + username/email.
- **L42**: закрывает `if`.
- **L43**: `next()` — пропускает запрос дальше (middleware успешно завершён).
- **L44**: закрывает callback `jwt.verify`.
- **L45**: закрывает `authenticateToken`.
- **L46**: пустая строка.

### generateToken (выдача JWT)

- **L47**: комментарий — генерация JWT.
- **L48**: комментарий — `username` хранится в `email` в БД ради совместимости.
- **L49**: экспорт `generateToken(userId, username, privateAccess=false)`.
- **L50**: если `JWT_SECRET` не задан…
- **L51**: бросает исключение — это ошибка конфигурации (токен нельзя сгенерировать).
- **L52**: закрывает `if`.
- **L53**: `jwt.sign(payload, secret, options)` — создаёт токен.
- **L54**: payload: `userId`, `email`, `username`, `privateAccess` (приводится к boolean).
- **L55**: секрет подписи `JWT_SECRET`.
- **L56**: опции: `expiresIn: '7d'` — токен живёт 7 дней.
- **L57**: закрывает `jwt.sign` и возвращает токен.
- **L58**: закрывает `generateToken`.
- **L59**: пустая строка.

### requirePrivateAccess (доступ к приватным разделам)

- **L60**: комментарий.
- **L61**: экспорт middleware `requirePrivateAccess`.
- **L62**: если в `req.user.privateAccess === true`…
- **L63**: `next()` — доступ разрешён.
- **L64**: закрывает `if`.
- **L65**: иначе возвращает HTTP 403 “Требуется приватный доступ”.
- **L66**: закрывает функцию.
- **L67**: пустая строка.

### verifyWebSocketToken (JWT для WS)

- **L68**: комментарий.
- **L69**: экспорт `verifyWebSocketToken(token)`.
- **L70**: `try {` — перехватывает ошибки jwt.verify.
- **L71**: если `JWT_SECRET` не задан — возвращает `null` (валидация невозможна).
- **L72**: возвращает payload `jwt.verify(token, JWT_SECRET)` если всё ок.
- **L73**: `catch` — ловит ошибки (invalid signature, expired, etc).
- **L74**: возвращает `null` при любой ошибке.
- **L75**: закрывает `catch`.
- **L76**: закрывает функцию.
- **L77**: пустая строка (конец файла).

---

## Appendix D — Построчный разбор `my_serve_chat_test/routes/auth.js`

Ниже — объяснение **каждой строки** файла `my_serve_chat_test/routes/auth.js`.

- **L1**: импорт `express` (Router).
- **L2**: импорт `express-rate-limit` (лимитер запросов).
- **L3**: импорт контроллеров auth: `register`, `login`, `getAllUsers`, `deleteAccount`, `changePassword`, `unlockPrivateAccess`.
- **L4**: импорт middleware `authenticateToken`.
- **L5**: пустая строка.
- **L6**: `express.Router()` — создаёт роутер для `/auth`.
- **L7**: пустая строка.

### unlockLimiter (анти-брутфорс приватного кода)

- **L8**: комментарий.
- **L9**: создаёт `unlockLimiter`.
- **L10**: окно 15 минут.
- **L11**: до 10 попыток.
- **L12**: standardHeaders.
- **L13**: legacyHeaders выключены.
- **L14**: сообщение при превышении лимита.
- **L15**: keyGenerator.
- **L16**: комментарий.
- **L17**: ключ лимита: `userId` если известен, иначе `req.ip`.
- **L18**: закрывает keyGenerator.
- **L19**: закрывает конфиг лимитера.
- **L20**: пустая строка.

### Публичные endpoints

- **L21**: комментарий.
- **L22**: `POST /auth/register` → `register`.
- **L23**: `POST /auth/login` → `login`.
- **L24**: пустая строка.

### Защищённые endpoints

- **L25**: комментарий.
- **L26**: `GET /auth/users` требует JWT → `getAllUsers`.
- **L27**: `DELETE /auth/user/:userId` требует JWT → `deleteAccount`.
- **L28**: `PUT /auth/user/:userId/password` требует JWT → `changePassword`.
- **L29**: `POST /auth/unlock-private` требует JWT + rate limit → `unlockPrivateAccess`.
- **L30**: пустая строка.
- **L31**: экспорт роутера.
- **L32**: пустая строка (конец файла).

---

## Appendix E — Построчный разбор `my_serve_chat_test/routes/chats.js`

Ниже — объяснение **каждой строки** файла `my_serve_chat_test/routes/chats.js`.

- **L1**: импорт `express`.
- **L2**: импорт chat‑контроллеров: `getChatsList`, `getUserChats`, `createChat`, `deleteChat`, `getChatMembers`, `addMembersToChat`, `removeMemberFromChat`, `leaveChat`.
- **L3**: импорт middleware `authenticateToken`.
- **L4**: пустая строка.
- **L5**: создаёт `router`.
- **L6**: пустая строка.
- **L7**: комментарий — все чаты требуют JWT.
- **L8**: `router.use(authenticateToken)` — защищает все маршруты ниже.
- **L9**: пустая строка.
- **L10**: комментарий — порядок роутов важен.
- **L11**: `GET /chats` → `getChatsList` (список с last message + unread).
- **L12**: `POST /chats/:id/leave` → `leaveChat`.
- **L13**: `GET /chats/:id/members` → `getChatMembers`.
- **L14**: `POST /chats/:id/members` → `addMembersToChat`.
- **L15**: `DELETE /chats/:id/members/:userId` → `removeMemberFromChat`.
- **L16**: `GET /chats/:id` → `getUserChats` (legacy; по факту использует userId из токена).
- **L17**: `POST /chats` → `createChat`.
- **L18**: `DELETE /chats/:id` → `deleteChat`.
- **L19**: пустая строка.
- **L20**: экспорт роутера.
- **L21**: пустая строка (конец файла).

---

## Appendix F — Построчный разбор `my_serve_chat_test/routes/messages.js`

Ниже — объяснение **каждой строки** файла `my_serve_chat_test/routes/messages.js`.

- **L1**: импорт `express`.
- **L2**: импорт message‑контроллеров (get/send/delete/clear/upload/read/edit/pin/reaction + search + around).
- **L3**: импорт middleware `authenticateToken`.
- **L4**: импорт multer‑middleware `uploadImage` (в `utils/uploadImage.js`) — обработка multipart.
- **L5**: пустая строка.
- **L6**: создаёт `router`.
- **L7**: пустая строка.
- **L8**: комментарий — все message routes требуют JWT.
- **L9**: `router.use(authenticateToken)` — защита всех маршрутов.
- **L10**: пустая строка.
- **L11**: комментарий — search/around должны быть раньше `/:chatId`.
- **L12**: `GET /messages/chat/:chatId/search` → `searchMessages`.
- **L13**: `GET /messages/chat/:chatId/around/:messageId` → `getMessagesAround`.
- **L14**: пустая строка.
- **L15**: `GET /messages/:chatId` → `getMessages` (пагинация).
- **L16**: `POST /messages` → `sendMessage`.
- **L17**: `PUT /messages/message/:messageId` → `editMessage`.

### upload-image с обработкой ошибок multer

- **L18**: комментарий.
- **L19**: `POST /messages/upload-image` — сначала промежуточный handler.
- **L20–L23**: `uploadImageMiddleware.fields([...])` — принимает до 2 файлов: `image` и `original`.
- **L23**: вызывает multer и получает `err`.
- **L24**: если есть ошибка…
- **L25**: логирует.
- **L26–L29**: возвращает HTTP 400 с деталями.
- **L30**: закрывает `if`.
- **L31**: `next()` — продолжить к контроллеру.
- **L32**: закрывает callback.
- **L33**: закрывает промежуточный handler и передаёт управление в `uploadImage`.

### Удаление/очистка

- **L34**: `DELETE /messages/message/:messageId` → `deleteMessage`.
- **L35**: `DELETE /messages/:chatId` → `clearChat`.
- **L36**: пустая строка.

### Статусы прочтения

- **L37**: комментарий.
- **L38**: `POST /messages/message/:messageId/read` → `markMessageAsRead`.
- **L39**: `POST /messages/chat/:chatId/read-all` → `markMessagesAsRead`.
- **L40**: пустая строка.

### Закрепления

- **L41**: комментарий.
- **L42**: `POST /messages/message/:messageId/pin` → `pinMessage`.
- **L43**: `DELETE /messages/message/:messageId/pin` → `unpinMessage`.
- **L44**: `GET /messages/chat/:chatId/pinned` → `getPinnedMessages`.
- **L45**: пустая строка.

### Реакции

- **L46**: комментарий.
- **L47**: `POST /messages/message/:messageId/reaction` → `addReaction`.
- **L48**: `DELETE /messages/message/:messageId/reaction` → `removeReaction`.
- **L49**: пустая строка.
- **L50**: экспорт роутера.
- **L51**: пустая строка (конец файла).

---

## Appendix G — Построчный разбор `lib/services/storage_service.dart`

Ниже — объяснение **каждой строки** файла `lib/services/storage_service.dart`.

> Этот файл — “локальная база” в приложении: сохраняет userId/userEmail/JWT/тему/флаг приватного доступа через `SharedPreferences`.

### Импорты и ключи

- **L1**: импорт `shared_preferences` — простое key/value хранилище на устройстве (и web-адаптация).
- **L2**: импорт `kIsWeb` и `kDebugMode` — флаги платформы/режима.
- **L3**: пустая строка.
- **L4**: объявление класса `StorageService` (статические методы).
- **L5**: ключ `_userIdKey` для сохранения userId.
- **L6**: ключ `_userEmailKey` для сохранения email/логина.
- **L7**: ключ `_tokenKey` для JWT.
- **L8**: ключ `_themeModeKey` для темы (dark/light).
- **L9**: префикс `_privateUnlockedPrefix` для приватных вкладок (зависит от userId).
- **L10**: пустая строка.

### saveUserData

- **L11**: комментарий — сохранение данных пользователя.
- **L12**: `saveUserData(userId, userEmail, token)` — сохраняет 3 строки.
- **L13**: `try` — ловим ошибки SharedPreferences.
- **L14**: получает `prefs` (инстанс SharedPreferences).
- **L15**: кладёт userId.
- **L16**: кладёт userEmail.
- **L17**: кладёт token.
- **L18**: лог “токен сохранен” (показывает первые 20 символов).
- **L19**: если это Web…
- **L20**: лог “платформа WEB”.
- **L21**: подсказка где смотреть (DevTools).
- **L22**: закрывает `if (kIsWeb)`.
- **L23**: `catch (e)` — если сохранение упало.
- **L24**: лог ошибки.
- **L25**: если web…
- **L26**: подсказка о проблеме с SharedPreferences на web.
- **L27**: закрывает `if`.
- **L28**: `rethrow` — пробрасывает ошибку наверх.
- **L29**: закрывает `catch`.
- **L30**: закрывает метод.
- **L31**: пустая строка.

### getUserData

- **L32**: комментарий — получение данных пользователя.
- **L33**: `getUserData()` возвращает `Map<String, String>?`.
- **L34**: `try`.
- **L35**: лог вызова.
- **L36**: получает `prefs`.
- **L37**: лог успеха.
- **L38**: пустая строка.
- **L39**: читает userId.
- **L40**: читает userEmail.
- **L41**: читает token.
- **L42**: пустая строка.
- **L43–L48**: отладочные логи значений и длины токена.
- **L49**: если все три значения не null…
- **L50**: лог “все данные найдены”.
- **L51**: лог “что возвращаем” (первые 20 символов токена).
- **L52–L56**: возвращает Map с `id/email/token`.
- **L57**: `else` — когда данных не хватает.
- **L58**: лог “не все данные найдены”.
- **L59–L61**: детализация, что есть/нет.
- **L62**: закрывает `else`.
- **L63**: возвращает `null` (нет полноценной сессии).
- **L64**: `catch (e)` — любые ошибки.
- **L65**: лог ошибки.
- **L66**: если debugMode…
- **L67**: лог stack trace текущего места.
- **L68**: закрывает `if`.
- **L69**: возвращает `null`.
- **L70**: закрывает `catch`.
- **L71**: закрывает метод.
- **L72**: пустая строка.

### getToken

- **L73**: комментарий.
- **L74**: `getToken()` — возвращает строку или null.
- **L75**: `try`.
- **L76**: получает `prefs`.
- **L77**: читает token.
- **L78**: если token не null…
- **L79**: лог “токен получен”.
- **L80**: если Web…
- **L81**: лог “WEB”.
- **L82**: закрывает `if`.
- **L83**: `else` — токена нет.
- **L84**: лог “токен не найден”.
- **L85**: если Web…
- **L86–L88**: подсказки где искать в DevTools.
- **L89**: закрывает `if`.
- **L90**: возвращает token (или null).
- **L91**: `catch` — ошибка получения.
- **L92**: лог ошибки.
- **L93**: если Web — подсказка.
- **L94–L95**: лог причины.
- **L96**: возвращает null.
- **L97**: закрывает `catch`.
- **L98**: закрывает метод.
- **L99**: пустая строка.

### clearUserData

- **L100**: комментарий.
- **L101**: `clearUserData()` — удаляет сохранённые ключи.
- **L102**: получает prefs.
- **L103**: читает userId (нужен для очистки приватного флага).
- **L104**: удаляет `_userIdKey`.
- **L105**: удаляет `_userEmailKey`.
- **L106**: удаляет `_tokenKey`.
- **L107**: если userId был…
- **L108**: удаляет приватный флаг для этого userId.
- **L109**: закрывает `if`.
- **L110**: закрывает метод.
- **L111**: пустая строка.

### private features unlocked (по userId)

- **L112**: комментарий.
- **L113**: `setPrivateFeaturesUnlocked(userId, unlocked)` — сохраняет bool.
- **L114**: получает prefs.
- **L115**: кладёт bool по ключу `private_features_unlocked_<userId>`.
- **L116**: закрывает метод.
- **L117**: пустая строка.
- **L118**: комментарий.
- **L119**: `isPrivateFeaturesUnlocked(userId)` — читает bool.
- **L120**: получает prefs.
- **L121**: возвращает bool или false по умолчанию.
- **L122**: закрывает метод.
- **L123**: пустая строка.

### Тема (dark/light)

- **L124**: комментарий.
- **L125**: `saveThemeMode(isDark)` — сохраняет bool темы.
- **L126**: `try`.
- **L127**: получает prefs.
- **L128**: кладёт bool по ключу `_themeModeKey`.
- **L129**: `catch` — ошибка.
- **L130**: лог ошибки.
- **L131**: закрывает `catch`.
- **L132**: закрывает метод.
- **L133**: пустая строка.
- **L134**: комментарий.
- **L135**: `getThemeMode()` — читает bool темы.
- **L136**: `try`.
- **L137**: получает prefs.
- **L138**: возвращает bool или false (светлая тема по умолчанию).
- **L139**: `catch`.
- **L140**: лог ошибки.
- **L141**: возвращает false.
- **L142**: закрывает `catch`.
- **L143**: закрывает метод.
- **L144–L145**: закрывают класс/файл.

---

## Appendix H — Построчный разбор `lib/services/http_service.dart`

Ниже — объяснение **каждой строки** файла `lib/services/http_service.dart`.

> Это “универсальный” HTTP клиент поверх `package:http`: формирует заголовки и вызывает GET/POST/PUT/DELETE. В проекте есть и другие сервисы (`auth_service.dart`, `messages_service.dart`, …) которые делают запросы напрямую, но этот класс остаётся полезным как единый слой.

- **L1**: импорт `dart:convert` — нужен для `jsonEncode`.
- **L2**: импорт `package:http` как `http` — HTTP клиент.
- **L3**: импорт `StorageService` — чтобы брать JWT.
- **L4**: пустая строка.
- **L5**: объявление класса `HttpService`.
- **L6**: `baseUrl` сервера Render.
- **L7**: пустая строка.

### _getHeaders

- **L8**: комментарий.
- **L9**: приватный метод `_getHeaders`, параметр `includeAuth`.
- **L10–L12**: базовые заголовки: JSON Content-Type.
- **L14**: если нужно включить авторизацию…
- **L15**: читает token из `StorageService`.
- **L16**: если token есть…
- **L17**: добавляет `Authorization: Bearer <token>`.
- **L18**: закрывает `if`.
- **L19**: закрывает `if (includeAuth)`.
- **L21**: возвращает headers.
- **L22**: закрывает метод.
- **L23**: пустая строка.

### GET

- **L24**: комментарий.
- **L25**: метод `get(endpoint, requireAuth=true)`.
- **L26**: формирует headers.
- **L27–L30**: делает `http.get` на `$baseUrl$endpoint`.
- **L31**: закрывает метод.
- **L32**: пустая строка.

### POST

- **L33**: комментарий.
- **L34**: метод `post(endpoint, body, requireAuth=true)`.
- **L35**: формирует headers.
- **L36–L40**: делает `http.post`, body сериализует `jsonEncode`.
- **L41**: закрывает метод.
- **L42**: пустая строка.

### PUT

- **L43**: комментарий.
- **L44**: метод `put(endpoint, body, requireAuth=true)`.
- **L45**: headers.
- **L46–L50**: `http.put`, `jsonEncode`.
- **L51**: закрывает метод.
- **L52**: пустая строка.

### DELETE

- **L53**: комментарий.
- **L54**: метод `delete(endpoint, body?, requireAuth=true)`.
- **L55**: headers.
- **L56–L60**: `http.delete`, тело опционально.
- **L61–L62**: закрывает метод и класс.
- **L63–L64**: пустые строки (конец файла).

---

## Appendix I — Деплой/окружения (Render) и переменные окружения

Этот раздел — “мануал эксплуатации”: **как запускать сервер**, какие переменные окружения обязательны и как их правильно выставлять на Render.

### I.1 Где крутится backend

Backend находится в папке `my_serve_chat_test/` и запускается командой, похожей на:
- `node index.js`

На Render это обычно **Web Service**.

### I.2 Обязательные переменные окружения (Render → Service → Environment)

Минимальный набор, без которого сервер либо не запустится, либо не будет работать корректно:

1) **`JWT_SECRET`**
- Назначение: секрет подписи/проверки JWT.
- Требование: **обязателен**. В production сервер не стартует без него.
- Важно: если поменять `JWT_SECRET`, все текущие токены станут невалидны → пользователям нужно перелогиниться.

2) **`DATABASE_URL`**
- Назначение: строка подключения PostgreSQL.
- Требование: обязателен для любого режима работы, иначе большинство эндпоинтов упадут.

3) **`PORT`** (обычно Render ставит сам)
- Назначение: порт, на котором слушает `index.js`.
- Как правило: не трогать, Render прокидывает автоматически.

Дополнительно (рекомендуется):

4) **`NODE_ENV`**
- `production` на боевом окружении.

5) **`ALLOWED_ORIGINS`**
- CSV список доменов для CORS (например: `https://ваш-домен.vercel.app,https://ваш-домен.com`).
- Примечание: в вашем сервере есть логика, которая также разрешает `.vercel.app` и localhost.

### I.3 Переменные для изображений (Object Storage)

Если вы используете загрузку изображений в Яндекс Object Storage:
- `YANDEX_ACCESS_KEY_ID`
- `YANDEX_SECRET_ACCESS_KEY`
- `YANDEX_BUCKET_NAME`
- (опционально) `AUTO_SETUP_CORS` — если поставить `'false'`, автоконфиг CORS для бакета отключится.

### I.4 Как добавить/обновить переменную на Render (пошагово)

1) Render Dashboard → **Services** → ваш backend service  
2) **Environment**  
3) **Add Environment Variable**  
4) Вводите Key/Value (без кавычек) → **Save Changes**  
5) Делаете **redeploy/restart** сервиса (Render обычно сам перезапускает после изменения env)

### I.5 Миграции базы данных (важно)

В проекте есть SQL‑миграции в `my_serve_chat_test/migrations/`. Они **не применяются автоматически** самим сервером.

Что это значит на практике:
- если вы добавили миграцию (например `add_unread_indexes.sql`), её нужно выполнить вручную на вашей Postgres (через psql/GUI/консоль Render).

Пример логики применения:
1) Подключиться к вашей БД (DATABASE_URL) через psql или GUI.
2) Выполнить содержимое файла миграции.

### I.6 Flutter клиент и baseUrl

Во многих сервисах Flutter жёстко задан:
- `https://my-server-chat.onrender.com`

Это значит:
- если вы меняете домен сервера, нужно обновлять baseUrl в Flutter сервисах (`lib/services/*.dart`).

---

## Appendix J — Построчный разбор `my_serve_chat_test/controllers/messagesController.js` (часть 1)

Этот файл — центральное “ядро” сообщений: чтение с пагинацией, форматирование под Flutter, реакции/реплаи/пересылка/пины/прочтения, поиск и “прыжок” к сообщению, загрузка изображений.

Файл большой, поэтому разбор идёт частями.

### J.1 Импорты

- **L1**: импорт `pool` из `db.js` — это пул соединений PostgreSQL, через него выполняются SQL запросы.
- **L2**: импорт `getWebSocketClients` — доступ к Map подключённых WS‑клиентов (userId → ws).
- **L3**: импорт функций загрузки/удаления изображений: `uploadImageMiddleware` (multer), `uploadToCloud`, `deleteImage`.
- **L4**: пустая строка.

### J.2 Helper `ensureChatMember`

Этот helper нужен, чтобы **любая операция над чат‑контентом** проверяла: “пользователь состоит в чате”.

- **L5**: объявляет `ensureChatMember(chatId, userId)` как async‑функцию.
- **L6**: парсит `chatId` в число (`chatIdNum`).
- **L7**: если `chatIdNum` не число — возвращает объект “ошибка”, HTTP 400.
- **L8**: пустая строка.
- **L9**: выполняет SQL `SELECT 1 FROM chat_users WHERE chat_id=$1 AND user_id=$2`.
- **L10**: SQL строка.
- **L11**: параметры запроса `[chatIdNum, userId]` — безопасно (prepared statement).
- **L12**: закрывает вызов `pool.query`.
- **L13**: если строк нет — пользователь не участник.
- **L14**: возвращает “ошибка”, HTTP 403.
- **L15**: закрывает `if`.
- **L16**: иначе возвращает “ok” и нормализованный `chatIdNum`.
- **L17**: закрывает helper.
- **L18**: пустая строка.

### J.3 `getMessages` — чтение сообщений чата с пагинацией + форматирование

#### Входные параметры

- Путь: `GET /messages/:chatId`
- Query:
  - `limit` — сколько сообщений вернуть (ограничено 1..200)
  - `offset` — сдвиг (используется в offset‑режиме)
  - `before` — messageId, чтобы грузить более старые (cursor‑режим)

#### Код (построчно)

- **L19**: экспорт `getMessages(req, res)` — контроллер Express.
- **L20**: берёт `chatId` из URL параметра.
- **L21**: берёт `currentUserId` из JWT (`req.user.userId`), это ключевой принцип безопасности.
- **L22**: пустая строка.
- **L23**: комментарий — блок пагинации.
- **L24**: читает `limit` из query и пытается распарсить.
- **L25**: читает `offset` из query и пытается распарсить.
- **L26**: нормализует `limit`:
  - если не число → 50
  - минимум 1
  - максимум 200
- **L27**: нормализует `offset`:
  - если не число → 0
  - минимум 0
- **L28**: читает `before` (cursor) из query.
- **L29**: пустая строка.
- **L30**: `try` — чтобы ловить ошибки БД.
- **L31**: комментарий — проверка доступа.
- **L32**: вызывает `ensureChatMember(chatId, currentUserId)`.
- **L33**: если `membership.ok` false…
- **L34**: возвращает `res.status(...).json({message})` с кодом 400/403.
- **L35**: закрывает `if`.
- **L36**: достаёт нормализованный `chatIdNum`.
- **L37**: пустая строка.

#### Выбор режима пагинации

- **L38**: объявляет `result` (результат запроса сообщений).
- **L39**: объявляет `totalCountResult` (результат запроса количества).
- **L40**: пустая строка.
- **L41**: если задан `beforeMessageId` → cursor‑режим.
- **L42**: парсит `beforeMessageId` как число.
- **L43**: если не число…
- **L44**: HTTP 400 “Некорректный параметр before”.
- **L45**: закрывает `if`.
- **L46–L47**: комментарий: грузим сообщения “старше” заданного ID; берём `limit+1`, чтобы понять есть ли ещё.

#### SQL в cursor‑режиме

- **L48**: выполняет SQL запрос.
- **L49–L61**: SELECT нужных полей сообщения + `sender_email` + `is_pinned`.
- **L62**: FROM messages.
- **L63**: JOIN users — чтобы получить email автора.
- **L64**: LEFT JOIN pinned_messages — флаг закрепления.
- **L65**: WHERE: чат совпадает и `messages.id < beforeIdNum` (только старые).
- **L66**: ORDER BY `messages.id DESC` — старые к более новым в выдаче (по id убыванию).
- **L67**: LIMIT `$3`.
- **L68**: параметры `[chatIdNum, beforeIdNum, limit+1]`.
- **L69**: пустая строка.
- **L70**: определяет `hasMoreMessages`: получили ли мы больше, чем `limit`.
- **L71**: вычисление boolean.
- **L72**: пустая строка.
- **L73**: комментарий — обрезаем до `limit`.
- **L74**: если `hasMoreMessages`…
- **L75**: `slice(0, limit)` — убираем лишнее.
- **L76**: закрывает `if`.
- **L77**: пустая строка.
- **L78**: комментарий — получаем total count.
- **L79–L82**: запрос `SELECT COUNT(*)` по чату.

#### Offset‑режим (когда before не задан)

- **L83**: `else` — offset‑режим.
- **L84–L85**: комментарий.
- **L86–L89**: тот же `COUNT(*)`, чтобы знать общее количество.
- **L90**: пустая строка.
- **L91**: `totalCount` — преобразует строку COUNT в int.
- **L92**: `actualOffset` — хитрая формула, чтобы вернуть “последние” сообщения:
  - берём `totalCount - limit - offset`
  - минимум 0
- **L93**: пустая строка.
- **L94**: выполняет SQL выборку сообщений.
- **L95–L107**: SELECT почти как в cursor‑режиме.
- **L108–L113**: WHERE чат, ORDER BY `created_at ASC`, LIMIT/OFFSET.
- **L114**: параметры `[chatIdNum, limit, actualOffset]`.
- **L115**: закрывает ветку `else`.
- **L116**: пустая строка.

#### Форматирование под Flutter

- **L117**: заново вычисляет `totalCount` из `totalCountResult`.
- **L118**: пустая строка.
- **L119**: комментарий — форматируем.
- **L120**: `Promise.all` по каждой строке — **важно**: это делает дополнительные запросы к БД на каждое сообщение.
- **L121**: комментарий — проверка прочтения.
- **L122–L125**: SQL `SELECT read_at FROM message_reads WHERE message_id=$1 AND user_id=$2`.
- **L126**: пустая строка.
- **L127**: `isRead` — прочитано ли.
- **L128**: `readAt` — время прочтения или null.
- **L129**: пустая строка.

#### Reply-to (сообщение, на которое отвечают)

- **L130**: комментарий.
- **L131**: `replyToMessage = null` по умолчанию.
- **L132**: если есть `reply_to_message_id`…
- **L133–L143**: запрос на получение “оригинального” сообщения для превью reply.
- **L144**: если нашли…
- **L145–L151**: формирует объект `replyToMessage` с минимальным набором полей.
- **L152**: закрывает `if`.
- **L153**: закрывает `if (row.reply_to_message_id)`.
- **L154**: пустая строка.

#### Reactions (реакции на сообщение)

- **L155**: комментарий.
- **L156–L168**: SQL выборка реакций + email автора реакции.
- **L169**: пустая строка.
- **L170–L177**: маппинг строк БД в массив `reactions`.
- **L178**: пустая строка.

#### Forwarded (переслано ли)

- **L179**: комментарий.
- **L180–L183**: проверка `message_forwards` для message_id.
- **L184**: `isForwarded` boolean.
- **L185**: `originalChatName` по умолчанию null.
- **L186**: если переслано и есть `original_chat_id`…
- **L187–L190**: достаёт имя оригинального чата.
- **L191–L193**: если найдено — сохраняет `originalChatName`.
- **L194**: закрывает `if`.
- **L195**: пустая строка.

#### Финальный объект сообщения

- **L196**: возвращает объект (то, что Flutter ожидает в JSON).
- **L197–L215**: поля сообщения + computed поля (`is_read`, `reply_to_message`, `reactions`, `is_forwarded`, `original_chat_name`, `is_pinned`).
- **L216**: закрывает map callback.
- **L217**: пустая строка.

#### pagination.hasMore + oldestMessageId

Этот блок завершает ответ так, чтобы Flutter мог подгружать старые сообщения по `before`.

- **L218**: комментарий.
- **L219**: объявляет `hasMore`.
- **L220–L235**: две ветки:
  - cursor: проверяет наличие сообщений с `id < minId`
  - offset: сравнивает `(offset + limit) < totalCount`
- **L237–L241**: вычисляет `oldestMessageId` как минимальный id в выдаче.
- **L243–L252**: отвечает JSON: `{ messages: ..., pagination: ... }`
- **L253–L256**: обработка ошибок: лог + HTTP 500.
- **L257**: закрывает `getMessages`.

> Следующая часть (Appendix J часть 2) разберёт: `sendMessage`, `editMessage`, `deleteMessage`, `clearChat`, read-all/read-one, pins, reactions.

---

## Appendix J — `messagesController.js` (часть 2): отправка/редактирование/удаление/прочтение/пины/реакции (концептуально построчно)

В этом файле функций много. Ниже я продолжаю “построчно”, но группирую по функциям: внутри каждой функции объясняю строку за строкой, а между функциями даю контекст.

> Примечание: в этой части файла также встречаются большие SQL блоки. Их строки я объясняю по смыслу (каждый SELECT/JOIN/WHERE/ORDER/LIMIT), чтобы не терять полезность на объёме.

### J.4 `sendMessage` — отправка сообщения + WebSocket рассылка

Блок начинается около **L533**.

- **L533**: экспорт `sendMessage(req, res)` — основной endpoint отправки.
- **L534**: комментарий: какие поля может прислать клиент.
- **L535**: деструктуризация body: `chat_id`, `content`, `image_url`, `original_image_url`, `reply_to_message_id`, `forward_from_message_id`, `forward_to_chat_ids`.
- **L537**: комментарий — берём userId из токена.
- **L538**: `user_id = req.user.userId` — автор сообщения.
- **L540–L549**: dev‑логирование вызова (безопаснее, чем логировать всегда).
- **L551**: валидация: должен быть `chat_id` и либо `content`, либо `image_url`.
- **L552**: если не так — HTTP 400.
- **L555**: комментарий — ветка пересылки.
- **L556–L558**: если есть `forward_from_message_id` и список чатов — делегирует в `forwardMessages(...)` и возвращает его результат.
- **L560**: `try` для основной логики отправки.
- **L561–L566**: парсит `chat_id` в число и валидирует, иначе 400.
- **L568–L576**: проверка членства в чате через `chat_users`, иначе 403 (security).
- **L578–L584**: вычисляет `message_type` (`text`, `image`, `text_image`) по наличию текста/картинки.
- **L587–L588**: парсит `reply_to_message_id` (если есть).
- **L590–L600**: dev‑лог “что вставляем”.

#### INSERT сообщения

- **L602–L606**: SQL `INSERT INTO messages (...) VALUES (...) RETURNING ...`:
  - сохраняет сообщение,
  - ставит `delivered_at = CURRENT_TIMESTAMP`,
  - сохраняет `reply_to_message_id`,
  - возвращает поля созданного сообщения.
- **L608–L609**: `senderEmail = req.user.email` — email/логин автора для ответа/WS.
- **L611**: `message = result.rows[0]` — созданное сообщение.

#### Reply preview в ответе

- **L613–L636**: если есть `reply_to_message_id`, делает SELECT оригинального сообщения и собирает компактный объект `replyToMessage`.

#### Формирование HTTP ответа

- **L638–L656**: собирает `response` в формате, который ждёт Flutter (поля + `is_read=false`, `reactions=[]`, `is_pinned=false`).

#### WebSocket рассылка участникам

- **L658**: комментарий.
- **L659–L717**: `try/catch` вокруг WS логики (сообщение уже в БД, поэтому WS ошибка не должна ломать запрос).
- **L660**: получает Map клиентов `clients`.
- **L661–L664**: получает список участников чата из `chat_users`.
- **L666–L679**: формирует `wsMessage` (тело события) и приводит `chat_id` к строке.
- **L681–L685**: dev‑логи участников и подключённых клиентов.
- **L687**: сериализует сообщение в JSON строку.
- **L689–L708**: циклом по участникам:
  - достаёт ws‑клиент по userId,
  - если подключён и открыт (`readyState===1`) → `send`,
  - иначе пропускает.
- **L710–L712**: dev‑лог сколько реально отправили.
- **L713–L717**: логирование WS ошибки, но запрос не падает.

#### Завершение запроса

- **L719**: `res.status(201).json(response)` — успешная отправка.
- **L720–L733**: общий `catch` — логирует детали и возвращает 500 (в dev добавляет stack).
- **L734**: закрывает `sendMessage`.

### J.5 `editMessage` — редактирование сообщения (только автор) + WS событие `message_edited`

Блок начинается около **L736**.

- **L737–L740**: читает `messageId` из params, `userId` из токена, `content/image_url` из body.
- **L742–L748**: валидации: нужен `messageId`, и должно быть что редактировать.
- **L750**: `try`.
- **L751–L763**: SELECT сообщения по id (чтобы узнать chat_id, автора, текущие поля).
- **L765–L767**: если нет — 404.
- **L769**: `message = ...`.
- **L771–L778**: доп. security: редактор должен быть участником чата.
- **L780–L785**: security: редактировать может только автор (`message.user_id == userId`), иначе 403.

#### Построение UPDATE динамически

- **L787–L790**: готовит массивы `updateFields/updateValues` и `paramIndex`.
- **L792–L795**: если передали content — добавляет `content = $N` и значение.
- **L797–L800**: если передали image_url — добавляет `image_url = $N` и значение.
- **L802–L803**: всегда добавляет `edited_at = CURRENT_TIMESTAMP` (не через параметр).
- **L804**: добавляет `messageId` последним параметром для WHERE.
- **L806–L811**: собирает SQL строку UPDATE (используя join списка полей).
- **L813–L814**: выполняет UPDATE и получает `updatedMessage`.

#### WS рассылка `message_edited`

- **L816–L845**: отправляет всем участникам чата ws событие с `type: 'message_edited'`.
- **L824–L835**: тело события включает id, chat_id, user_id, контент, edited_at и sender_email.

#### HTTP ответ

- **L847–L857**: возвращает 200 с обновлённым сообщением.
- **L858–L861**: ошибка → 500.
- **L862**: закрывает функцию.

### J.6 `deleteMessage` — удаление (только автор) + удаление изображений + WS событие `message_deleted`

Блок начинается около **L864**.

Ключевые идеи:
- пользователь может удалить только своё сообщение;
- проверяется членство в чате;
- если у сообщения есть image_url/original_image_url — пытаемся удалить файлы в облаке;
- затем удаляем запись в БД и рассылаем WS уведомление.

Строки, которые видны в фрагменте:
- **L865–L872**: берёт messageId, userId, валидирует messageId.
- **L875–L888**: SELECT сообщения по id (chat_id, user_id, image_url, message_type).
- **L890–L892**: если нет — 404.
- **L894–L895**: сохраняет `message` и `chatId`.
- **L897–L905**: проверяет существование чата.
- **L907–L915**: проверяет, что удаляет автор (иначе 403).
- **L917–L927**: проверяет членство в чате.
- **L929–L938**: пытается удалить сжатое изображение из облака (ошибка не блокирует удаление сообщения).

> Дальше по файлу (не в этом фрагменте) аналогично удаляется `original_image_url`, затем удаляется строка messages, затем шлётся WS `message_deleted` участникам.

---

Следующая часть (J.7+) будет покрывать:
- `clearChat` (очистка чата),
- `markMessageAsRead` / `markMessagesAsRead`,
- `pinMessage` / `unpinMessage` / `getPinnedMessages`,
- `addReaction` / `removeReaction`,
всё также построчно.

---

## Appendix J — `messagesController.js` (часть 3): `deleteMessage`, `clearChat`, `markMessageAsRead` (построчно на реальных строках файла)

Ниже — продолжение построчного разбора по конкретным строкам файла (с привязкой к номерам строк, как они в файле сейчас).

### J.6 (детально) `deleteMessage` — строки L864–L1004

- **L864**: комментарий “Удаление одного сообщения”.
- **L865**: экспорт `deleteMessage(req, res)`.
- **L866**: берёт `messageId` из URL `/messages/message/:messageId`.
- **L867–L868**: берёт `userId` из токена (`req.user.userId`) — это авторизация.
- **L870–L872**: если `messageId` пустой — 400.
- **L874**: `try`.

#### 1) Получить сообщение из БД

- **L875**: комментарий.
- **L876–L888**: SELECT сообщения по id:
  - берёт `chat_id`, `user_id` (автора), `image_url`, `message_type`, `created_at`, content.
- **L890–L892**: если не найдено — 404.
- **L894**: `message = messageCheck.rows[0]`.
- **L895**: `chatId = message.chat_id`.

#### 2) Проверить, что чат существует

- **L897**: комментарий.
- **L898–L901**: `SELECT id FROM chats WHERE id=$1`.
- **L903–L905**: если чата нет — 404.

#### 3) Проверка прав: удалять может только автор

- **L907**: комментарий.
- **L908–L910**: нормализует `message.user_id` и `userId` в строки (сравнение без типов).
- **L911–L915**: если не совпадают — 403.

#### 4) Проверка членства в чате

- **L917**: комментарий.
- **L918–L921**: `SELECT 1 FROM chat_users WHERE chat_id=$1 AND user_id=$2`.
- **L923–L927**: если не участник — 403.

#### 5) Удаление изображений из Object Storage (best effort)

- **L929**: комментарий.
- **L930**: если `message.image_url` есть…
- **L931–L934**: пытается удалить сжатое изображение.
- **L934–L937**: при ошибке логирует и продолжает (важно: не блокировать удаление сообщения).
- **L940**: комментарий про оригинал.
- **L941**: если `message.original_image_url` есть…
- **L942–L945**: пытается удалить оригинал.
- **L945–L948**: при ошибке логирует и продолжает.

#### 6) Удаление сообщения из БД

- **L951**: комментарий.
- **L952**: `DELETE FROM messages WHERE id=$1`.

#### 7) WebSocket уведомление всем участникам

- **L954**: комментарий.
- **L955**: `try` (ошибка WS не должна ломать удаление).
- **L956**: берёт `clients` (Map userId→ws).
- **L957–L960**: SELECT всех участников `chat_users` для чата.
- **L962–L967**: формирует ws payload `type: 'message_deleted'` с `message_id`, `chat_id`, `user_id`.
- **L969–L970**: отладочные логи (их можно бы тоже ограничить dev-режимом, но сейчас они без токенов/секретов).
- **L972**: сериализует JSON.
- **L974**: счётчик отправленных.
- **L975–L987**: цикл по участникам:
  - берёт ws клиента,
  - если открыт — `send`,
  - ловит ошибки на отдельного клиента.
- **L989**: лог “скольким отправили”.
- **L990–L993**: если WS упал — логирует, но продолжает.

#### 8) HTTP ответ

- **L995–L998**: возвращает 200 “Сообщение успешно удалено”.
- **L1000–L1003**: общий `catch` — лог и 500.
- **L1004**: конец `deleteMessage`.

---

### J.7 `clearChat` — строки L1006–L1060

- **L1006**: комментарий.
- **L1007**: экспорт `clearChat(req, res)`.
- **L1008**: берёт `chatId` из URL `/messages/:chatId`.
- **L1009–L1010**: userId из токена.
- **L1012–L1014**: если chatId пустой — 400.
- **L1016**: `try`.

#### 1) Проверить, что чат существует + кто создатель

- **L1017**: комментарий.
- **L1018–L1021**: `SELECT id, created_by FROM chats WHERE id=$1`.
- **L1023–L1025**: если чата нет — 404.

#### 2) Жёсткое правило: чистить чат может только создатель

- **L1027**: комментарий.
- **L1028**: `creatorId = created_by`.
- **L1029–L1031**: если creatorId != текущий userId — 403.

#### 3) Проверка членства (доп. защита)

- **L1033**: комментарий.
- **L1034–L1037**: `SELECT 1 FROM chat_users WHERE chat_id=$1 AND user_id=$2`.
- **L1039–L1043**: если не участник — 403.

#### 4) Удаление сообщений чата

- **L1045**: комментарий.
- **L1046–L1049**: `DELETE FROM messages WHERE chat_id=$1`.
- **L1051–L1054**: ответ 200 + сколько строк удалено (`rowCount`).
- **L1056–L1059**: ошибки → 500.
- **L1060**: конец `clearChat`.

---

### J.8 `markMessageAsRead` — строки L1062–…

- **L1062**: комментарий.
- **L1063**: экспорт `markMessageAsRead`.
- **L1064**: `try`.
- **L1065–L1066**: достаёт messageId из params и userId из токена.
- **L1068**: комментарий.
- **L1069–L1072**: SELECT `chat_id` сообщения (чтобы знать, где проверять членство).
- **L1074–L1076**: если сообщения нет — 404.
- **L1078**: `chatId` сообщения.
- **L1080**: комментарий.
- **L1081–L1084**: проверяет, что userId состоит в чате (`chat_users`).
- **L1086–L1088**: если нет — 403.
- **L1090**: комментарий.
- **L1091–L1096**: UPSERT в `message_reads`:
  - вставляет `(message_id, user_id, read_at)`
  - при конфликте обновляет `read_at`.
- **L1098**: комментарий.
- **L1099–L1102**: SELECT автора сообщения (`user_id`) чтобы уведомить его.
- **L1104–L1117**: если автор найден и у него есть ws‑соединение — отправляет событие `type: 'message_read'`.

> Следом в файле идут `markMessagesAsRead` (прочитать всё в чате), пересылка, пины, реакции, поиск, around, uploadImage. Я продолжаю в следующем расширении Appendix J (часть 4), чтобы сохранить качество “построчно”.

---

## Appendix K — Построчный разбор `my_serve_chat_test/websocket/websocket.js`

Этот файл поднимает WebSocket сервер (библиотека `ws`) и хранит мапу подключённых клиентов `clients: Map<userId, ws>`.

> Важно: в проекте часть событий отправляется через WebSocket из контроллеров (например `sendMessage`, `deleteMessage`, `editMessage`), а в этом файле реализованы входящие WS‑сообщения (`mark_read`, `send`).

### K.1 Импорты и состояние

- **L1**: импорт `WebSocketServer` из пакета `ws` — это WS сервер для Node.
- **L2**: импорт `pool` — запросы к PostgreSQL из WS‑обработчиков.
- **L3**: импорт `verifyWebSocketToken` — проверка JWT для WS подключения.
- **L4**: пустая строка.
- **L5**: `clients = new Map()` — хранит соответствие `userId -> ws соединение`.
- **L6**: пустая строка.

### K.2 getWebSocketClients()

- **L7**: комментарий.
- **L8**: экспорт функции `getWebSocketClients()`.
- **L9**: возвращает `clients` (используется контроллерами сообщений для рассылки).
- **L10**: закрывает функцию.
- **L11**: пустая строка.

### K.3 setupWebSocket(server)

- **L12**: экспорт `setupWebSocket(server)` — принимает HTTP server (тот же, что слушает Express).
- **L13**: создаёт `wss = new WebSocketServer({ server })` — WS поверх существующего HTTP.
- **L14**: пустая строка.

#### Подключение клиента

- **L15**: `wss.on('connection', (ws, req) => { ... })` — срабатывает на новое WS подключение.
- **L16**: комментарий — токен берём из query.
- **L17**: парсит URL запроса подключения (нужно, чтобы достать query параметры).
- **L18**: `token = url.searchParams.get('token')` — ожидается `?token=<JWT>`.
- **L19**: пустая строка.
- **L20**: если токена нет…
- **L21–L23**: в dev логирует причину.
- **L24**: закрывает соединение с кодом 1008 (policy violation) и текстом.
- **L25**: `return` — прекращает обработку.
- **L26**: закрывает `if`.

#### Проверка JWT токена

- **L28**: комментарий.
- **L29**: `decoded = verifyWebSocketToken(token)` — проверяет подпись/срок.
- **L30**: если не декодировалось…
- **L31–L33**: dev‑лог.
- **L34**: `ws.close(1008, 'Недействительный токен')`.
- **L35**: `return`.
- **L36**: закрывает `if`.

#### Привязка соединения к userId

- **L38**: `userId = decoded.userId.toString()` — ключ мапы.
- **L39**: `userEmail = decoded.email` — логин/почта из токена (для формирования сообщений).
- **L41–L43**: dev‑лог подключения.
- **L44**: `clients.set(userId, ws)` — сохраняет соединение.

### K.4 ws.on('message') — входящие WS сообщения

- **L46**: обработчик входящих сообщений от клиента.
- **L47**: `try` — JSON.parse может упасть.
- **L48**: `data = JSON.parse(message)` — ожидается JSON строка.
- **L49**: пустая строка.

#### K.4.1 type === 'mark_read'

- **L50**: комментарий.
- **L51**: если `data.type === 'mark_read'`…
- **L52**: достаёт `messageId`.
- **L53**: достаёт `chatId`.
- **L55–L57**: если нет обязательных полей — просто `return`.

**Проверка членства в чате:**
- **L59**: комментарий.
- **L60–L63**: `SELECT 1 FROM chat_users WHERE chat_id=$1 AND user_id=$2`.
  - важный момент: берёт `userId` из токена (а не из входного сообщения).
- **L65–L67**: если не участник — `return` (молча игнорируем).

**Запись прочтения (upsert):**
- **L69**: комментарий.
- **L70–L75**: UPSERT в `message_reads`.

**Уведомление автору сообщения:**
- **L77**: комментарий.
- **L78–L81**: SELECT `user_id` автора сообщения.
- **L83–L94**: если автор найден и он подключён — отправляем `type: 'message_read'`.
- **L96**: `return` — чтобы не продолжать обработку дальше.
- **L97**: закрывает `if (mark_read)`.

#### K.4.2 type === 'send'

- **L99**: если `data.type === 'send'`…
- **L100**: комментарий.
- **L101**: достаёт `chatIdFinal` (поддерживает два имени поля: `chat_id` или `chatId`).
- **L102**: достаёт `content`.
- **L104–L106**: если нет чата или контента — `return`.

**Проверка членства:**
- **L108–L113**: `SELECT 1 FROM chat_users WHERE chat_id=$1 AND user_id=$2`.
- **L114–L119**: если не участник — dev‑лог и `return`.

**INSERT сообщения:**
- **L121**: комментарий.
- **L122–L126**: вставляет сообщение в БД (упрощённый путь: только text).

**Сборка события:**
- **L128–L129**: `senderEmailFinal = userEmail` (из токена).
- **L131–L138**: формирует `fullMessage` с полями сообщения.

**Рассылка всем участникам чата:**
- **L140**: комментарий.
- **L141–L144**: SELECT участников `chat_users`.
- **L146–L151**: для каждого участника, если клиент подключён — отправляет JSON.
- **L152**: закрывает `if (send)`.

#### Ошибки JSON/логики

- **L153**: `catch (e)` — если JSON.parse упал или SQL упал.
- **L154**: лог ошибки.
- **L155**: закрывает catch.
- **L156**: закрывает обработчик `ws.on('message')`.

### K.5 ws.on('close')

- **L158**: обработчик закрытия соединения.
- **L159**: удаляет `clients.delete(userId)` — чтобы не рассылать на мёртвое соединение.
- **L160**: закрывает handler.
- **L161**: закрывает `connection` handler.

### K.6 Лог запуска

- **L163**: лог “WebSocket сервер запущен”.
- **L164**: закрывает `setupWebSocket`.
- **L165**: конец файла.


