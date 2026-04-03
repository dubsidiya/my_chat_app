# 🔍 Структура кода - Быстрая справка

## 📍 Где что находится

### Flutter: Основные паттерны

#### Сервисы → API вызовы
Все сервисы используют `HttpService` для запросов:
```dart
// Пример: lib/services/auth_service.dart
Future<void> loginExample(HttpService httpService, String email, String password) async {
  final response = await httpService.post(
    '/auth/login',
    {
      'email': email,
      'password': password,
    },
    requireAuth: false,
  );
  print(response.statusCode);
}
```

#### Хранение токена
```dart
// lib/services/storage_service.dart
Future<void> tokenExample(String userId, String email, String token) async {
  await StorageService.saveUserData(userId, email, token);
  final savedToken = await StorageService.getToken();
  print(savedToken);
}
```

#### Навигация
- `MainTabsScreen` - главный экран с табами
- `HomeScreen` → `ChatScreen` - переход к чату
- `StudentsScreen` → `StudentDetailScreen` - детали студента

---

### Сервер: Основные паттерны

#### Контроллеры → Роуты
```javascript
// routes/auth.js
router.post('/login', login); // login из controllers/authController.js
```

#### Аутентификация
```javascript
// middleware/auth.js
router.use(authenticateToken); // защищает все роуты
```

#### Работа с БД
```javascript
// controllers/*.js
const result = await pool.query('SELECT * FROM users WHERE id = $1', [userId]);
```

---

## 🗂️ Быстрый поиск по функционалу

### Аутентификация
- **Flutter**: `lib/services/auth_service.dart` + `lib/screens/login_screen.dart`
- **Сервер**: `my_serve_chat_test/controllers/authController.js` + `routes/auth.js`

### Чаты и сообщения
- **Flutter**: 
  - `lib/services/chats_service.dart`
  - `lib/services/messages_service.dart`
  - `lib/screens/chat_screen.dart`
- **Сервер**: 
  - `controllers/chatsController.js` + `routes/chats.js`
  - `controllers/messagesController.js` + `routes/messages.js`
  - `websocket/websocket.js`

### Студенты и занятия
- **Flutter**: 
  - `lib/services/students_service.dart`
  - `lib/screens/students_screen.dart`
  - `lib/screens/add_lesson_screen.dart`
- **Сервер**: 
  - `controllers/studentsController.js`
  - `controllers/lessonsController.js`
  - `controllers/transactionsController.js`
  - `routes/students.js`

### Отчеты
- **Flutter**: 
  - `lib/services/reports_service.dart`
  - `lib/screens/reports_chat_screen.dart`
  - `lib/screens/report_text_view_screen.dart` — просмотр и копирование текста отчёта
- **Сервер**: 
  - `controllers/reportsController.js`
  - `routes/reports.js`

---

## 🔑 Ключевые файлы для редактирования

### Изменить базовый URL API
```dart
// lib/services/http_service.dart, строка 6
final String baseUrl = 'https://my-server-chat.onrender.com';
```

### Изменить стиль приложения
```dart
// lib/main.dart, строки 34-93
final theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
  useMaterial3: true,
);
```

### Добавить новый API endpoint
1. Добавить метод в контроллер (`controllers/*.js`)
2. Добавить роут (`routes/*.js`)
3. Добавить метод в сервис Flutter (`lib/services/*.dart`)
4. Использовать в экране (`lib/screens/*.dart`)

### Изменить схему БД
1. Создать миграцию (`migrations/*.sql`)
2. Обновить модель Flutter (`lib/models/*.dart`)
3. Обновить контроллеры сервера

---

## 🐛 Отладка

### Проверить токен
```dart
// lib/services/storage_service.dart
Future<void> debugToken() async {
  final token = await StorageService.getToken();
  print('Token: $token');
}
```

### Логи сервера
```javascript
// controllers/*.js
console.log('🔐 Auth check:', req.method, req.path);
console.log('✅ Success:', data);
console.error('❌ Error:', error);
```

### Проверить подключение к БД
```bash
# Сервер автоматически проверяет при запуске
# См. db.js, строки 27-36
```

---

## 📋 Чеклист для новых фич

- [ ] Создать/обновить модель (`lib/models/`)
- [ ] Создать/обновить сервис (`lib/services/`)
- [ ] Создать/обновить экран (`lib/screens/`)
- [ ] Создать/обновить контроллер (`controllers/`)
- [ ] Создать/обновить роут (`routes/`)
- [ ] Обновить схему БД (если нужно) (`migrations/`)
- [ ] Добавить аутентификацию (если нужно) (`middleware/auth.js`)
- [ ] Протестировать на клиенте и сервере

---

## 🔗 Связи между компонентами

```
Flutter Screen
    ↓ использует
Flutter Service
    ↓ вызывает
HttpService
    ↓ отправляет HTTP запрос
Server Route
    ↓ вызывает
Server Controller
    ↓ использует
Database (PostgreSQL)
```

---

## 💡 Полезные команды

### Сервер
```bash
cd my_serve_chat_test
npm start              # запуск
npm run check-setup    # проверка настроек
npm run migrate-passwords  # миграция паролей
```

### Flutter
```bash
flutter pub get        # установка зависимостей
flutter run            # запуск
flutter clean          # очистка кэша
```

---

*Создано для быстрой навигации по коду*

