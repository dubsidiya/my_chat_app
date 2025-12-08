# Проверка эндпоинтов сервера

## Проблема: 404 при создании чата

Ошибка 404 означает, что сервер не находит эндпоинт `POST /chats`.

## Что нужно проверить на сервере

### 1. Проверьте роуты на сервере

Убедитесь, что на сервере зарегистрирован роут для создания чата:

**Для Express.js (Node.js):**
```javascript
// Должен быть роут вида:
app.post('/chats', createChatController);
// или
router.post('/chats', createChatController);
```

**Для других фреймворков:**
- Убедитесь, что есть обработчик для `POST /chats`

### 2. Проверьте базовый URL

Убедитесь, что нет префикса `/api`:

- Если сервер использует `/api/chats`, то в приложении нужно использовать `$baseUrl/api/chats`
- Если сервер использует просто `/chats`, то текущий код правильный

### 3. Проверьте логи сервера на Render

1. Зайдите на https://dashboard.render.com
2. Откройте ваш сервис
3. Перейдите в раздел **Logs**
4. Попробуйте создать чат снова
5. Посмотрите, появляются ли логи о запросе `POST /chats`

**Если запрос не доходит до сервера:**
- Проблема с роутингом или сервер не запущен

**Если запрос доходит, но возвращает 404:**
- Роут не зарегистрирован или путь неправильный

### 4. Проверьте доступные эндпоинты

Попробуйте в браузере или через curl:

```bash
# Проверка базового URL
curl https://my-server-chat.onrender.com/

# Проверка эндпоинта создания чата
curl -X POST https://my-server-chat.onrender.com/chats \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Chat","userIds":["1"]}'
```

### 5. Возможные решения

#### Вариант А: Добавить префикс `/api`

Если сервер использует префикс `/api`, обновите `chats_service.dart`:

```dart
Future<Chat> createChat(String name, List<String> userIds) async {
  final response = await http.post(
    Uri.parse('$baseUrl/api/chats'), // Добавить /api
    // ...
  );
}
```

#### Вариант Б: Проверить регистрацию роутов

Убедитесь, что на сервере роуты зарегистрированы правильно:

```javascript
// Пример для Express.js
const express = require('express');
const router = express.Router();

router.post('/chats', async (req, res) => {
  // Логика создания чата
  try {
    const { name, userIds } = req.body;
    // ... создание чата
    res.status(201).json(chat);
  } catch (error) {
    res.status(500).json({ message: 'Ошибка сервера' });
  }
});

// Не забудьте зарегистрировать роутер:
app.use('/', router); // или app.use('/api', router);
```

## Текущие эндпоинты в приложении

Приложение использует следующие эндпоинты:

- `POST /auth/login` - вход
- `POST /auth/register` - регистрация
- `GET /chats/:userId` - получение чатов пользователя
- `POST /chats` - создание чата (❌ возвращает 404)
- `GET /messages/:chatId` - получение сообщений
- `POST /messages` - отправка сообщения
- `WebSocket: wss://my-server-chat.onrender.com` - WebSocket для сообщений

## Что нужно сделать

1. ✅ Проверить логи сервера на Render
2. ✅ Убедиться, что роут `POST /chats` зарегистрирован
3. ✅ Проверить, нет ли префикса `/api` в роутах
4. ✅ Протестировать эндпоинт через curl или Postman

## Если нужно изменить URL в приложении

Если выяснится, что нужен другой путь (например, `/api/chats`), сообщите - я обновлю код.

