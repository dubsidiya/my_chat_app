# Том 2. Dart: асинхронность, файлы, отладка

Второй том учебника. Здесь разбираем **асинхронный код** (Future, async/await, Stream), работу с **файлами и каталогами**, основы **тестирования**, **типичные ошибки и отладку**, а также кратко — **стиль кода**.

**Предполагается:** вы прошли Том 1 (переменные, функции, классы, JSON).

**Что дальше:** Том 3 — Flutter: виджеты и интерфейс.

---

## Оглавление тома 2

1. [Зачем нужна асинхронность](#1-зачем-нужна-асинхронность)
2. [Future и async/await](#2-future-и-asyncawait)
3. [Ошибки в асинхронном коде](#3-ошибки-в-асинхронном-коде)
4. [Stream: поток данных](#4-stream-поток-данных)
5. [Работа с файлами и папками](#5-работа-с-файлами-и-папками)
6. [Тесты: основы](#6-тесты-основы)
7. [Типичные ошибки и отладка](#7-типичные-ошибки-и-отладка)
8. [Стиль кода и соглашения](#8-стиль-кода-и-соглашения)
9. [Проверь себя](#9-проверь-себя)

---

## 1. Зачем нужна асинхронность

Часть операций занимает время: запрос в интернет, чтение или запись файла, ожидание таймера. Если бы программа «замирала» и ждала ответа, приложение бы подвисало — пользователь не мог бы нажимать кнопки, интерфейс бы не обновлялся.

**Асинхронность** — способ организовать код так, чтобы во время ожидания программа продолжала работать. Мы «запускаем» долгую операцию и подписываемся на результат: когда он готов, выполняется следующий код (например, обновление экрана). В Dart для этого используются **Future** (одно значение в будущем) и **Stream** (поток значений во времени).

---

## 2. Future и async/await

**Future** — объект, который представляет результат операции, завершающейся позже. У него тип **Future<T>**, где T — тип результата (например, `Future<String>`, `Future<List<Chat>>`).

**async** и **await** позволяют писать асинхронный код почти как обычный последовательный: функция помечается **async**, а перед вызовом другой асинхронной функции ставится **await** — выполнение приостановится до получения результата, но поток не блокируется.

### 2.1. Объявление асинхронной функции

```dart
Future<String> fetchGreeting() async {
  await Future.delayed(Duration(seconds: 1));  // имитация задержки
  return 'Привет!';
}
```

Вызов с **await** возможен только внутри **async**-функции:

```dart
Future<void> main() async {
  String text = await fetchGreeting();
  print(text);  // через секунду: Привет!
}
```

### 2.2. Пример из проекта: вход пользователя

В `lib/screens/login_screen.dart` при нажатии «Войти» вызывается асинхронная функция `_login()`:

```dart
void _login() async {
  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });

  try {
    final userData = await _authService.loginUser(username, password);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
    // переход на следующий экран...
  } catch (e) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}
```

- `await _authService.loginUser(...)` — ждём ответ сервера, не блокируя UI.
- Перед обновлением состояния проверяем **mounted** — виджет может быть уже снят с экрана, тогда setState вызывать нельзя.

### 2.3. Несколько await подряд

Операции выполняются по очереди: вторая начнётся после завершения первой.

```dart
Future<void> loadData() async {
  final user = await fetchUser();
  final chats = await fetchChats(user.id);
  setState(() {
    _chats = chats;
  });
}
```

### 2.4. Параллельное выполнение

Если два запроса не зависят друг от друга, их можно запустить одновременно через **Future.wait**:

```dart
Future<void> loadAll() async {
  final results = await Future.wait([
    fetchUser(),
    fetchSettings(),
  ]);
  final user = results[0];
  final settings = results[1];
}
```

### 2.5. Таймаут

Чтобы операция не висела бесконечно, задают **timeout**:

```dart
final response = await http.get(uri).timeout(
  const Duration(seconds: 10),
  onTimeout: () => throw Exception('Таймаут запроса'),
);
```

В проекте так сделано, например, в `AuthService.changePassword` и `AuthService.deleteAccount`.

---

## 3. Ошибки в асинхронном коде

Исключения в **async**-функции ведут себя так же, как в обычном коде: если не перехватить их в **try/catch**, они «всплывут» к вызывающему. При **await** исключение из Future будет выброшено в месте await, поэтому оборачивать вызов в try/catch нужно вокруг await.

```dart
try {
  final data = await fetchData();
  use(data);
} catch (e) {
  print('Ошибка: $e');
}
```

**Важно во Flutter:** после await перед setState всегда проверять **mounted** — за время ожидания пользователь мог уйти с экрана и виджет уже размонтирован. Иначе получите ошибку «setState() called after dispose()».

```dart
final data = await fetchData();
if (!mounted) return;
setState(() => _data = data);
```

---

## 4. Stream: поток данных

**Stream** — последовательность событий во времени. В отличие от Future (одно значение), Stream может выдавать много значений: например, нажатия кнопки, сообщения по WebSocket, прогресс загрузки.

### 4.1. Подписка на Stream

```dart
stream.listen(
  (data) => print('Получено: $data'),
  onError: (e) => print('Ошибка: $e'),
  onDone: () => print('Поток завершён'),
);
```

### 4.2. Отмена подписки

Подписка возвращает **StreamSubscription**. Её нужно отменять при уходе с экрана, иначе утечка памяти и лишние срабатывания.

```dart
StreamSubscription? _subscription;

@override
void initState() {
  super.initState();
  _subscription = WebSocketService.instance.stream.listen((event) {
    if (!mounted) return;
    setState(() { /* обновить UI */ });
  });
}

@override
void dispose() {
  _subscription?.cancel();
  super.dispose();
}
```

В `lib/screens/home_screen.dart` так подписываются на новые сообщения по WebSocket и в **dispose** вызывают `_wsSubscription?.cancel()`.

### 4.3. Преобразование Stream

Методы **map**, **where**, **asyncMap** и др. позволяют преобразовывать или фильтровать события:

```dart
stream
  .where((e) => e is Map && e['type'] == 'message')
  .map((e) => Message.fromJson(e))
  .listen((msg) => addMessage(msg));
```

---

## 5. Работа с файлами и папками

В Dart для работы с файловой системой используется класс **File** и **Directory** из **dart:io** (в Flutter на платформах с файловой системой они доступны; для web — ограничения).

### 5.1. Чтение и запись файла

```dart
import 'dart:io';

Future<String> readFile(String path) async {
  final file = File(path);
  return await file.readAsString();
}

Future<void> writeFile(String path, String content) async {
  final file = File(path);
  await file.writeAsString(content);
}
```

### 5.2. Пути и каталоги

```dart
import 'dart:io';

final dir = Directory('/path/to/folder');
if (await dir.exists()) {
  await for (var entity in dir.list()) {
    print(entity.path);
  }
}

// Создать каталог (включая родительские)
await Directory('path/to/new/folder').create(recursive: true);
```

### 5.3. Во Flutter: assets и path_provider

- **Assets** — файлы, упакованные с приложением (например, `assets/config.json`). Читаются через **rootBundle.loadString('assets/config.json')** — см. Том 1, парсинг JSON из файла.
- **path_provider** — пакет для получения путей к временной и постоянной директории приложения (кэш, документы). После `getApplicationDocumentsDirectory()` или `getTemporaryDirectory()` вы формируете путь к файлу и работаете с ним через **File(path)**.

В проекте my_chat_app локальное хранилище реализовано через **SharedPreferences** и **FlutterSecureStorage**, а не через сырые файлы — см. Том 5.

---

## 6. Тесты: основы

Тесты позволяют проверять логику без запуска всего приложения. В Dart используют пакет **test**.

### 6.1. Простой тест

Файл `test/user_test.dart`:

```dart
import 'package:test/test.dart';

void main() {
  test('User.fromJson создаёт объект из Map', () {
    final json = {'id': '1', 'email': 'a@b.com', 'name': 'Test'};
    final user = User.fromJson(json);
    expect(user.id, '1');
    expect(user.email, 'a@b.com');
  });
}
```

Запуск: `dart test` или `flutter test`.

### 6.2. expect

- **expect(фактическое, ожидаемое)** — равенство.
- **expect(() => код, throwsException)** — проверка на исключение.
- **expect(list, hasLength(3))** — матчеры для коллекций.

### 6.3. group

Группировка тестов по смыслу:

```dart
group('User', () {
  test('fromJson с полными данными', () { ... });
  test('fromJson с пустым name', () { ... });
});
```

---

## 7. Типичные ошибки и отладка

### 7.1. setState() called after dispose()

**Причина:** после **await** виджет уже размонтирован, а вы вызываете setState.  
**Решение:** перед setState проверять **if (!mounted) return;**.

### 7.2. Null check operator used on a null value

**Причина:** использовали **!** для переменной, которая оказалась null.  
**Решение:** проверять на null или использовать **??** и безопасные типы **?**.

### 7.3. Ошибки парсинга JSON

**Причина:** не тот тип (сервер вернул строку вместо числа), нет ключа.  
**Решение:** приводить типы явно, использовать **??** и вспомогательные функции вроде **_parseInt**, **_parseBool** (как в моделях проекта).

### 7.4. Отладка: print и debugPrint

В коде можно выводить отладочную информацию:

```dart
if (kDebugMode) {
  print('Значение: $variable');
}
```

**debugPrint** — то же, но не обрезает длинные строки. В release-сборке логи можно отключить проверкой **kDebugMode**.

### 7.5. Трассировка стека

При перехвате исключения полезно сохранять **StackTrace**:

```dart
try {
  await something();
} catch (e, stackTrace) {
  if (kDebugMode) {
    print('$e\n$stackTrace');
  }
  rethrow;
}
```

В **main.dart** проекта глобальная обработка ошибок настроена через **runZonedGuarded** и **FlutterError.onError**.

---

## 8. Стиль кода и соглашения

- **Именование:** переменные и функции — **lowerCamelCase**, классы — **UpperCamelCase**, константы — **lowerCamelCase** или **SCREAMING_CAPS** для констант уровня библиотеки.
- **private:** идентификаторы с подчёркивания в начале (**_privateField**) видны только внутри файла.
- **Фигурные скобки** для веток if/else и циклов — даже для одной строки (рекомендация Effective Dart).
- **Форматирование:** `dart format .` или в IDE «Format Document».

Официальный гайд: [Effective Dart](https://dart.dev/guides/language/effective-dart).

---

## 9. Проверь себя

1. Напиши асинхронную функцию `delayAndReturn(int seconds)`, которая ждёт указанное количество секунд и возвращает строку `'Готово'`. Вызови с await из main.
2. Объясни, зачем перед setState после await проверять **mounted**.
3. В проекте найди место, где отменяется подписка на WebSocket (Stream). Почему это делают в dispose?
4. Напиши один тест для модели User: fromJson с полями id, email — проверь, что поля совпадают.

**Что дальше:** Том 3 — Flutter: виджеты, дерево, State, компоновка, темы.

---

*Том 2 входит в полный учебник. План томов — docs/TUTORIAL_INDEX.md (папка docs).*
