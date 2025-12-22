# 🏛️ Архитектура приложения

## Общая схема

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Client (lib/)                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Screens    │→ │   Services   │→ │  HttpService │     │
│  │  (UI Layer)  │  │ (Business)   │  │  (API Calls) │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│         ↓                  ↓                  ↓            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Models     │  │   Storage    │  │  WebSocket   │     │
│  │  (Data)      │  │ (Local DB)   │  │  (Real-time) │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            ↕ HTTP/WebSocket
┌─────────────────────────────────────────────────────────────┐
│              Node.js Server (my_serve_chat_test/)           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │    Routes    │→ │ Controllers  │→ │  Middleware  │     │
│  │  (Endpoints) │  │  (Business)  │  │   (Auth)     │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│         ↓                  ↓                  ↓            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  WebSocket   │  │   Database   │  │   Utils      │     │
│  │   Server     │  │  (PostgreSQL)│  │ (Validation) │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Поток данных

### 1. Аутентификация
```
User Input (LoginScreen)
    ↓
AuthService.login()
    ↓
HttpService.post('/auth/login')
    ↓
Server: routes/auth.js → controllers/authController.js
    ↓
Database: SELECT user WHERE email = ?
    ↓
JWT Token Generation
    ↓
StorageService.saveUserData()
    ↓
Navigate to MainTabsScreen
```

### 2. Отправка сообщения
```
User Input (ChatScreen)
    ↓
MessagesService.sendMessage()
    ↓
HttpService.post('/messages')
    ↓
Server: routes/messages.js → controllers/messagesController.js
    ↓
Database: INSERT INTO messages
    ↓
WebSocket Broadcast
    ↓
All Connected Clients Receive Message
```

### 3. Создание отчета
```
User Input (ReportsChatScreen)
    ↓
ReportsService.createReport()
    ↓
HttpService.post('/reports')
    ↓
Server: routes/reports.js → controllers/reportsController.js
    ↓
Parse Report Content → Create Lessons
    ↓
Database: INSERT INTO reports, lessons, transactions
    ↓
Return Report with Lessons Count
```

## Структура базы данных

```
users
  ├── id (PK)
  ├── email (UNIQUE)
  ├── password (HASHED)
  └── created_at

chats
  ├── id (PK)
  ├── name
  ├── created_by (FK → users.id)
  └── created_at

chat_users (Many-to-Many)
  ├── chat_id (FK → chats.id)
  ├── user_id (FK → users.id)
  └── joined_at

messages
  ├── id (PK)
  ├── chat_id (FK → chats.id)
  ├── user_id (FK → users.id)
  ├── content
  └── created_at

students
  ├── id (PK)
  ├── name
  ├── parent_name
  ├── phone
  ├── email
  ├── notes
  ├── created_by (FK → users.id)
  └── created_at

lessons
  ├── id (PK)
  ├── student_id (FK → students.id)
  ├── lesson_date
  ├── lesson_time
  ├── duration_minutes
  ├── price
  ├── notes
  ├── created_by (FK → users.id)
  └── created_at

transactions
  ├── id (PK)
  ├── student_id (FK → students.id)
  ├── amount
  ├── type (deposit/lesson/refund)
  ├── description
  ├── lesson_id (FK → lessons.id, nullable)
  ├── created_by (FK → users.id)
  └── created_at

reports
  ├── id (PK)
  ├── report_date
  ├── content
  ├── created_by (FK → users.id)
  ├── is_edited
  └── created_at
```

## Слои приложения

### Flutter (Client)

#### Presentation Layer
- **Screens** (`lib/screens/`) - UI компоненты
- **Widgets** - переиспользуемые виджеты

#### Business Logic Layer
- **Services** (`lib/services/`) - бизнес-логика, API вызовы
- **Models** (`lib/models/`) - модели данных

#### Data Layer
- **StorageService** - локальное хранилище
- **HttpService** - HTTP клиент
- **WebSocket** - real-time соединение

### Node.js (Server)

#### API Layer
- **Routes** (`routes/`) - определение endpoints
- **Middleware** (`middleware/`) - аутентификация, валидация

#### Business Logic Layer
- **Controllers** (`controllers/`) - обработка запросов, бизнес-логика

#### Data Layer
- **Database** (`db.js`) - подключение к PostgreSQL
- **Queries** - SQL запросы в контроллерах

#### Real-time Layer
- **WebSocket** (`websocket/`) - real-time обновления

## Безопасность

### Аутентификация
```
Client Request
    ↓
Authorization: Bearer <JWT_TOKEN>
    ↓
Middleware: authenticateToken()
    ↓
JWT Verification
    ↓
Extract userId, email
    ↓
Attach to req.user
    ↓
Controller Access
```

### Хеширование паролей
```
User Password
    ↓
bcryptjs.hash(password, 10)
    ↓
Stored in Database
    ↓
Login: bcryptjs.compare(password, hash)
```

### Rate Limiting
```
/auth/login, /auth/register
    ↓
express-rate-limit
    ↓
Max 5 requests per 15 minutes
    ↓
Block if exceeded
```

## WebSocket Architecture

```
Client Connection
    ↓
WebSocket Handshake
    ↓
Token Verification (JWT)
    ↓
Add to Connected Clients Map
    ↓
Message Received
    ↓
Broadcast to Chat Members
    ↓
All Clients in Chat Receive Update
```

## Обработка ошибок

### Flutter
```dart
try {
  final result = await service.method();
} catch (e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Ошибка: $e'))
  );
}
```

### Server
```javascript
try {
  const result = await pool.query(...);
  res.json({ success: true, data: result.rows });
} catch (error) {
  console.error('Error:', error);
  res.status(500).json({ message: error.message });
}
```

## Развертывание

### Сервер (Render.com)
- Environment Variables: DATABASE_URL, JWT_SECRET, ALLOWED_ORIGINS
- Auto-deploy from Git
- PostgreSQL database

### Клиент (Vercel/Flutter Web)
- Build: `flutter build web`
- Static files deployment
- CORS настроен на сервере

---

*Диаграммы созданы для визуализации архитектуры*

