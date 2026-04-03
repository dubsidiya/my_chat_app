# 📱 Обзор приложения My Chat App

## 🏗️ Архитектура

Приложение состоит из двух основных частей:
1. **Flutter клиент** (`lib/`) - мобильное/веб приложение
2. **Node.js сервер** (`my_serve_chat_test/`) - REST API + WebSocket сервер

---

## 📂 Структура проекта

### Flutter приложение (`lib/`)

#### Модели данных (`lib/models/`)
- `user.dart` - модель пользователя
- `chat.dart` - модель чата
- `message.dart` - модель сообщения
- `student.dart` - модель студента/ученика
- `lesson.dart` - модель занятия
- `report.dart` - модель отчета

#### Сервисы (`lib/services/`)
- `http_service.dart` - базовый HTTP клиент (baseUrl: `https://my-server-chat.onrender.com`)
- `storage_service.dart` - локальное хранилище (SharedPreferences)
- `auth_service.dart` - аутентификация (login, register)
- `chats_service.dart` - управление чатами
- `messages_service.dart` - отправка/получение сообщений
- `students_service.dart` - управление студентами
- `reports_service.dart` - управление отчетами

#### Экраны (`lib/screens/`)
- `main.dart` - точка входа, проверка авторизации
- `login_screen.dart` - экран входа
- `register_screen.dart` - регистрация
- `main_tabs_screen.dart` - главный экран с табами (Чаты, Учет занятий, Отчеты)
- `home_screen.dart` - список чатов
- `chat_screen.dart` - экран чата с сообщениями
- `students_screen.dart` - список студентов
- `student_detail_screen.dart` - детали студента
- `add_student_screen.dart` - добавление студента
- `add_lesson_screen.dart` - добавление занятия
- `deposit_screen.dart` - пополнение баланса
- `bank_statement_screen.dart` - выписка по счету
- `reports_chat_screen.dart` - создание отчетов
- `report_text_view_screen.dart` - просмотр и копирование текста отчёта (правка — через конструктор)
- `add_members_dialog.dart` - диалог добавления участников
- `chat_members_dialog.dart` - список участников чата

---

### Node.js сервер (`my_serve_chat_test/`)

#### Основные файлы
- `index.js` - точка входа, настройка Express, CORS, WebSocket
- `db.js` - подключение к PostgreSQL (DATABASE_URL из env)
- `package.json` - зависимости и скрипты

#### Роуты (`routes/`)
- `auth.js` - аутентификация (register, login, users, password)
- `chats.js` - управление чатами и участниками
- `messages.js` - сообщения
- `students.js` - студенты, занятия, транзакции
- `reports.js` - отчеты
- `bankStatement.js` - выписки

#### Контроллеры (`controllers/`)
- `authController.js` - логика аутентификации (335 строк)
- `chatsController.js` - логика чатов
- `messagesController.js` - логика сообщений
- `studentsController.js` - логика студентов
- `lessonsController.js` - логика занятий
- `transactionsController.js` - логика транзакций
- `reportsController.js` - логика отчетов
- `bankStatementController.js` - логика выписок

#### Middleware (`middleware/`)
- `auth.js` - JWT аутентификация (authenticateToken, generateToken)

#### WebSocket (`websocket/`)
- `websocket.js` - WebSocket сервер для real-time сообщений

#### Утилиты (`utils/`)
- `validation.js` - валидация данных

#### Миграции (`migrations/`)
- `add_students_tables.sql` - таблицы студентов
- `add_reports_tables.sql` - таблицы отчетов

---

## 🔌 API Endpoints

### Аутентификация (`/auth`)
- `POST /auth/register` - регистрация (публичный)
- `POST /auth/login` - вход (публичный, rate-limited)
- `GET /auth/users` - список пользователей (требует токен)
- `DELETE /auth/user/:userId` - удаление аккаунта (требует токен)
- `PUT /auth/user/:userId/password` - смена пароля (требует токен)

### Чаты (`/chats`)
- `GET /chats/:id` - получить чаты пользователя (требует токен)
- `POST /chats` - создать чат (требует токен)
- `DELETE /chats/:id` - удалить чат (требует токен)
- `GET /chats/:id/members` - участники чата (требует токен)
- `POST /chats/:id/members` - добавить участников (требует токен)
- `DELETE /chats/:id/members/:userId` - удалить участника (требует токен)

### Сообщения (`/messages`)
- `GET /messages/:chatId` - получить сообщения (требует токен)
- `POST /messages` - отправить сообщение (требует токен)
- `DELETE /messages/:id` - удалить сообщение (требует токен)
- `DELETE /messages/chat/:chatId` - очистить чат (требует токен)

### Студенты (`/students`)
- `GET /students` - список студентов (требует токен)
- `POST /students` - создать студента (требует токен)
- `PUT /students/:id` - обновить студента (требует токен)
- `DELETE /students/:id` - удалить студента (требует токен)
- `GET /students/:id/balance` - баланс студента (требует токен)
- `GET /students/:id/transactions` - транзакции студента (требует токен)
- `GET /students/:studentId/lessons` - занятия студента (требует токен)
- `POST /students/:studentId/lessons` - создать занятие (требует токен)
- `DELETE /students/lessons/:id` - удалить занятие (требует токен)
- `POST /students/:studentId/deposit` - пополнить баланс (требует токен)

### Отчеты (`/reports`)
- `GET /reports` - список отчетов (требует токен)
- `GET /reports/:id` - получить отчет (требует токен)
- `POST /reports` - создать отчет (требует токен)
- `PUT /reports/:id` - обновить отчет (требует токен)
- `DELETE /reports/:id` - удалить отчет (требует токен)

### Выписки (`/bank-statement`)
- (см. `routes/bankStatement.js`)

---

## 🗄️ База данных (PostgreSQL)

### Основные таблицы

#### Пользователи и чаты
- `users` - пользователи (id, email, password, created_at)
- `chats` - чаты (id, name, created_by, created_at)
- `chat_users` - связь пользователей с чатами (many-to-many)
- `messages` - сообщения (id, chat_id, user_id, content, created_at)

#### Студенты и занятия
- `students` - студенты (id, name, parent_name, phone, email, notes, created_by)
- `lessons` - занятия (id, student_id, lesson_date, lesson_time, duration_minutes, price, notes)
- `transactions` - транзакции (id, student_id, amount, type: deposit/lesson/refund, description, lesson_id)

#### Отчеты
- `reports` - отчеты (id, report_date, content, created_by, is_edited, created_at)
- (связанные таблицы в миграциях)

### Индексы
- Оптимизированы запросы по chat_id, user_id, created_at
- Индексы для студентов, занятий, транзакций

---

## 🔐 Безопасность

### Аутентификация
- JWT токены (7 дней валидности)
- Пароли хешируются через bcryptjs
- Middleware `authenticateToken` проверяет токен в заголовке `Authorization: Bearer <token>`

### Rate Limiting
- `/auth/login` и `/auth/register` - максимум 5 запросов за 15 минут

### CORS
- Настроен для работы с Vercel, localhost, Render.com
- Разрешены поддомены `.vercel.app` и `.netlify.app`

---

## 🌐 WebSocket

- Реал-тайм обновления сообщений
- Аутентификация через JWT токен
- Подключение: `ws://` или `wss://` (зависит от окружения)

---

## 📦 Зависимости

### Flutter (pubspec.yaml)
- `http: ^0.13.6` - HTTP запросы
- `web_socket_channel: ^3.0.3` - WebSocket
- `shared_preferences: ^2.2.2` - локальное хранилище
- `intl: ^0.19.0` - форматирование дат
- `file_picker: ^6.1.1` - выбор файлов

### Node.js (package.json)
- `express: ^4.18.2` - веб-фреймворк
- `pg: ^8.11.0` - PostgreSQL клиент
- `jsonwebtoken: ^9.0.2` - JWT
- `bcryptjs: ^2.4.3` - хеширование паролей
- `ws: ^8.13.0` - WebSocket сервер
- `cors: ^2.8.5` - CORS middleware
- `express-rate-limit: ^7.1.5` - rate limiting
- `multer: ^1.4.5-lts.1` - загрузка файлов
- `xlsx: ^0.18.5` - работа с Excel
- `csv-parser: ^3.0.0` - парсинг CSV

---

## 🔧 Переменные окружения (сервер)

```env
DATABASE_URL=postgresql://user:password@host/dbname
JWT_SECRET=your-secret-key
ALLOWED_ORIGINS=https://my-chat-app.vercel.app,http://localhost:3000
PORT=3000
NODE_ENV=production
```

---

## 🚀 Запуск

### Сервер
```bash
cd my_serve_chat_test
npm install
npm start
```

### Flutter приложение
```bash
flutter pub get
flutter run
```

---

## 📱 Основной функционал

1. **Чаты** - создание чатов, добавление участников, обмен сообщениями в реальном времени
2. **Учет занятий** - управление студентами, создание занятий, отслеживание баланса
3. **Отчеты** - создание текстовых отчетов с автоматическим парсингом занятий

---

## 📝 Примечания

- Сервер развернут на Render.com: `https://my-server-chat.onrender.com`
- Flutter приложение может быть развернуто на Vercel для веб-версии
- База данных: PostgreSQL (Supabase/Neon/Render)
- Все запросы (кроме login/register) требуют JWT токен в заголовке Authorization

---

*Последнее обновление: $(date)*

