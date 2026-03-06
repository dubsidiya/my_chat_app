# Том 5. Сеть и данные: HTTP, API, хранилище, WebSocket

Пятый том — **работа с сетью и локальными данными**: HTTP-запросы к API, заголовки авторизации, хранение токена и настроек (SharedPreferences, secure storage), а также **WebSocket** для событий в реальном времени. Примеры из проекта my_chat_app.

**Предполагается:** Тома 1–4 (Dart, async/await, виджеты, навигация).

**Что дальше:** Том 6 — разбор проекта my_chat_app целиком.

---

## Оглавление тома 5

1. [HTTP: запросы и ответы](#1-http-запросы-и-ответы)
2. [Пакет http и базовый запрос](#2-пакет-http-и-базовый-запрос)
3. [Авторизация: токен в заголовке](#3-авторизация-токен-в-заголовке)
4. [Конфигурация API: базовый URL](#4-конфигурация-api-базовый-url)
5. [Хранение данных: SharedPreferences](#5-хранение-данных-sharedpreferences)
6. [Безопасное хранение токена](#6-безопасное-хранение-токена)
7. [WebSocket: соединение в реальном времени](#7-websocket-соединение-в-реальном-времени)
8. [Сервисы в проекте: кто за что отвечает](#8-сервисы-в-проекте-кто-за-что-отвечает)
9. [Типичные ошибки и таймауты](#9-типичные-ошибки-и-таймауты)
10. [Проверь себя](#10-проверь-себя)

---

## 1. HTTP: запросы и ответы

Приложение общается с сервером по протоколу **HTTP**. Клиент отправляет **запрос** (URL, метод GET/POST/PUT/DELETE, заголовки, тело), сервер возвращает **ответ** (код состояния — 200, 401, 404, 500 — и тело, часто в формате JSON).

- **GET** — получить данные (список чатов, сообщения).
- **POST** — создать или отправить (вход, регистрация, отправка сообщения).
- **PUT / PATCH** — обновить (смена пароля, профиль).
- **DELETE** — удалить (удаление аккаунта, чата).

Код ответа **200** — успех, **201** — создано, **400** — неверный запрос, **401** — не авторизован, **404** — не найдено, **500** — ошибка сервера.

---

## 2. Пакет http и базовый запрос

В проекте используется пакет **http**. Импорт: `import 'package:http/http.dart' as http;`.

**GET:**
```dart
final response = await http.get(
  Uri.parse('https://api.example.com/chats'),
  headers: {'Content-Type': 'application/json'},
);
```

**POST с телом JSON:**
```dart
final response = await http.post(
  Uri.parse('https://api.example.com/auth/login'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'username': username, 'password': password}),
);
```

**Чтение ответа:**
- **response.statusCode** — код (200, 401, ...).
- **response.body** — тело ответа (строка). Для JSON: `jsonDecode(response.body)`.

Пример из **AuthService.loginUser** (lib/services/auth_service.dart):
```dart
final response = await http.post(
  Uri.parse('$baseUrl/auth/login'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'username': username, 'password': password}),
);
if (response.statusCode == 200) {
  final data = jsonDecode(response.body);
  // сохранить токен, перейти на главный экран
} else if (response.statusCode == 401) {
  throw Exception('Неверный логин или пароль');
}
```

---

## 3. Авторизация: токен в заголовке

После входа сервер возвращает **токен**. Его сохраняют и при каждом запросе к защищённому API передают в заголовке **Authorization**:

```
Authorization: Bearer <токен>
```

В проекте заголовки формируются в методе **_getAuthHeaders()** в сервисах:

```dart
Future<Map<String, String>> _getAuthHeaders() async {
  final token = await StorageService.getToken();
  final headers = <String, String>{
    'Content-Type': 'application/json',
  };
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  return headers;
}
```

Использование: `final headers = await _getAuthHeaders();` затем `http.get(uri, headers: headers)`.

---

## 4. Конфигурация API: базовый URL

Адрес сервера выносят в конфиг, чтобы не менять его в десятках мест. В проекте — **lib/config/api_config.dart**:

```dart
class ApiConfig {
  static const String _defaultBaseUrl = 'https://reollity.duckdns.org';

  static String get baseUrl {
    final v = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: _defaultBaseUrl,
    ).trim();
    if (v.isEmpty) return _defaultBaseUrl;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }
}
```

При сборке можно переопределить: `flutter run --dart-define=API_BASE_URL=https://мой-сервер`.

В сервисах: `final String baseUrl = ApiConfig.baseUrl;`, затем `Uri.parse('$baseUrl/chats')`, `Uri.parse('$baseUrl/auth/login')` и т.д.

---

## 5. Хранение данных: SharedPreferences

**SharedPreferences** — простое ключ-значение хранилище (строки, числа, булевы значения). Данные сохраняются между запусками приложения.

```dart
import 'package:shared_preferences/shared_preferences.dart';

final prefs = await SharedPreferences.getInstance();
await prefs.setString('user_id', '123');
await prefs.setBool('sound_enabled', true);

final userId = prefs.getString('user_id');
final soundOn = prefs.getBool('sound_enabled') ?? true;
```

В проекте **StorageService** (lib/services/storage_service.dart) использует SharedPreferences для **userId**, **userEmail**, **displayName**, **avatarUrl**, порядка чатов, флага EULA, настроек звука и вибрации. Токен на мобильных хранится не в SharedPreferences, а в secure storage — см. ниже.

---

## 6. Безопасное хранение токена

Токен доступа не должен быть доступен другим приложениям и скриптам. На платформах с файловой системой используют **FlutterSecureStorage** (пакет **flutter_secure_storage**): данные хранятся в защищённом хранилище ОС. На Web secure storage недоступен, поэтому в проекте на Web токен хранится в SharedPreferences (с риском при XSS — в описании кода это отмечено).

В **StorageService**:
- при сохранении пользователя: если **kIsWeb** — пишем токен в prefs, иначе — в **FlutterSecureStorage**;
- при чтении токена — аналогично; есть миграция со старого хранения в prefs на secure.

```dart
static const FlutterSecureStorage _secure = FlutterSecureStorage();
// ...
if (kIsWeb) {
  await prefs.setString(_tokenKey, token);
} else {
  await _secure.write(key: _tokenKey, value: token);
  await prefs.remove(_tokenKey);
}
```

---

## 7. WebSocket: соединение в реальном времени

Чтобы новые сообщения появлялись без перезагрузки, используется **WebSocket** — постоянное двустороннее соединение. Сервер может в любой момент отправить событие (например, «новое сообщение в чате»).

В проекте **WebSocketService** (lib/services/websocket_service.dart) — синглтон. Он:
- подключается с токеном (в URL на Web: `?token=...`, на мобильных — заголовок Authorization);
- получает события и отдаёт их через **stream**;
- при обрыве соединения пытается переподключиться.

Подписка на экране (например, HomeScreen):
```dart
_wsSubscription = WebSocketService.instance.stream.listen((event) {
  if (!mounted) return;
  if (event is Map && event['chat_id'] != null) {
    _loadChats();  // обновить список чатов
  }
});
```

В **dispose** подписку отменяют: **\_wsSubscription?.cancel()**.

---

## 8. Сервисы в проекте: кто за что отвечает

| Сервис | Назначение |
|--------|------------|
| **AuthService** | Вход (login), регистрация (register), смена пароля, удаление аккаунта, обновление профиля/аватара, fetchMe, unlockPrivateAccess. HTTP-запросы к /auth/..., сохранение данных через StorageService. |
| **StorageService** | Токен (get/save, через secure storage или prefs), данные пользователя (getUserData, saveUserData, clearUserData), порядок чатов, EULA, настройки звука/вибрации, приватные функции. Только локальное хранилище. |
| **ChatsService** | Список чатов (fetchChats), создание чата, папки (fetchFolders, createFolder, renameFolder, deleteFolder, setChatFolderId), удаление чата, вступление по инвайт-коду. Заголовки через _getAuthHeaders(). |
| **MessagesService** | Сообщения чата (fetchMessages, fetchMessagesPaginated), отправка текста/файла/изображения, реакции, редактирование. Использует LocalMessagesService для кэша при офлайне. |
| **WebSocketService** | Один общий WebSocket. connectIfNeeded(), stream, disconnect(). Вызывается при старте приложения и при возврате из фона (didChangeAppLifecycleState). |
| **LocalMessagesService** | Кэш сообщений для офлайн-режима. init(), getMessages(chatId), сохранение при получении с сервера. |

---

## 9. Типичные ошибки и таймауты

- **Сеть недоступна** — запрос бросает исключение. Оборачивать в try/catch и показывать пользователю сообщение или кнопку «Повторить».
- **401 Unauthorized** — токен истёк или не передан. Обычно перенаправляют на экран входа и очищают сохранённые данные.
- **Таймаут** — долгий запрос. Использовать **.timeout(Duration(seconds: 10), onTimeout: () => throw ...)**.
- **Парсинг JSON** — неверный формат или неожиданный тип. Обрабатывать в try/catch, логировать и показывать понятное сообщение.

В проекте таймауты заданы, например, в **AuthService.changePassword** и **deleteAccount**; проверка на 401 и разбор тела ошибки — в методах AuthService и в других сервисах.

---

## 10. Проверь себя

1. Как в проекте передаётся токен в HTTP-запрос? Найди _getAuthHeaders в любом сервисе.
2. Где хранится токен на телефоне и где на Web? Открой StorageService.getToken и saveUserData.
3. Зачем нужен WebSocket в чате и как экран подписывается на новые сообщения? Найди _subscribeToNewMessages в HomeScreen.
4. Напиши пример: GET-запрос к `$baseUrl/chats` с заголовком Authorization, разбор ответа в List<Chat> (используй Chat.fromJson).

**Что дальше:** Том 6 — разбор проекта my_chat_app: main.dart, экраны, сервисы, модели, типичные задачи.

---

*Том 5 входит в полный учебник. План — docs/TUTORIAL_INDEX.md.*
