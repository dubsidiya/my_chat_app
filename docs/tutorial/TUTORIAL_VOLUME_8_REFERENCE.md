# Том 8. Справочник: словарик и частые ошибки

Восьмой том — **справочный**: краткий словарик терминов, синтаксис Dart и Flutter, типичные ошибки и ссылки на документацию. Удобно держать под рукой при чтении кода и других томов.

**Что дальше:** можно вернуться к любому тому для углубления или к Тому 6–7 для практики.

---

## Оглавление

1. [Словарик терминов](#1-словарик-терминов)
2. [Краткий синтаксис Dart](#2-краткий-синтаксис-dart)
3. [Краткий синтаксис Flutter](#3-краткий-синтаксис-flutter)
4. [Частые ошибки и решения](#4-частые-ошибки-и-решения)
5. [Ссылки на документацию](#5-ссылки-на-документацию)

---

## 1. Словарик терминов

| Термин | Краткое определение |
|--------|----------------------|
| **Dart** | Язык программирования для Flutter-приложений. |
| **Flutter** | Фреймворк для построения UI (iOS, Android, Web). |
| **Виджет (widget)** | Элемент интерфейса: кнопка, текст, экран, список. |
| **StatelessWidget** | Виджет без изменяемого состояния; только параметры. |
| **StatefulWidget** | Виджет с состоянием (State); обновление через setState. |
| **BuildContext** | Контекст сборки; доступ к теме, Navigator, ScaffoldMessenger. |
| **setState** | Метод State: пометить виджет для перерисовки с новыми данными. |
| **Future** | Обещание результата асинхронной операции. |
| **async / await** | Синтаксис асинхронного кода: await ждёт Future. |
| **Stream** | Поток событий во времени (подписка listen, отмена cancel). |
| **JSON** | Текстовый формат данных; парсинг — jsonDecode, сборка — jsonEncode. |
| **fromJson / toJson** | Фабричный конструктор и метод модели для перевода Map ↔ объект. |
| **HTTP** | Протокол запросов; методы GET, POST, PUT, DELETE. |
| **Токен** | Строка авторизации; заголовок Authorization: Bearer <token>. |
| **SharedPreferences** | Локальное хранилище ключ–значение (строки, числа, bool). |
| **Navigator** | Управление стеком экранов: push, pop, pushReplacement, pushAndRemoveUntil. |
| **mounted** | Свойство State: true, пока виджет в дереве; перед setState после await проверять. |
| **null-safety** | В Dart переменные по умолчанию не null; nullable — тип с `?`. |

---

## 2. Краткий синтаксис Dart

- Переменные: `тип имя = значение;`, `final тип имя = значение;`.
- Условие: `if (условие) { } else { }`.
- Цикл: `for (var x in list) { }`, `for (int i = 0; i < n; i++) { }`, `while (усл) { }`.
- Функция: `тип имя(тип1 арг1, тип2 арг2) { return значение; }`.
- async: `Future<тип> имя() async { final x = await f(); return x; }`.
- Класс: `class Name { final тип поле; Name({required this.поле}); factory Name.fromJson(Map<String, dynamic> j) => ... }`.
- Null: `тип?`, `x ?? default`, `x!`.
- try/catch: `try { } catch (e) { }`.

---

## 3. Краткий синтаксис Flutter

- MaterialApp: `MaterialApp(theme: ..., home: ...)`.
- Scaffold: `Scaffold(appBar: AppBar(...), body: ...)`.
- Компоновка: `Column(children: [...])`, `Row(children: [...])`, `Expanded(child: ...)`.
- Список: `ListView.builder(itemCount: n, itemBuilder: (c, i) => ...)`.
- Кнопки: `ElevatedButton(onPressed: () {}, child: Text('...'))`.
- Поле ввода: `TextField(controller: c, decoration: InputDecoration(...))`.
- Навигация: `Navigator.push(context, MaterialPageRoute(builder: (_) => Screen()));`, `Navigator.pop(context);` или `Navigator.pop(context, результат)`.
- Диалог: `showDialog(context: context, builder: (c) => AlertDialog(...));`.
- SnackBar: `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('...')));`.

---

## 4. Частые ошибки и решения

| Ошибка / ситуация | Решение |
|-------------------|--------|
| setState() called after dispose() | Перед setState после await проверить `if (!mounted) return;`. |
| Null check operator used on a null value | Не использовать `!` без уверенности; использовать `?` и `??`. |
| Ошибка парсинга JSON | Проверять ключи через `??`, приводить типы (.toString(), int.tryParse), обрабатывать вложенные объекты. |
| Запрос не отправляет токен | Убедиться, что _getAuthHeaders() вызывается и результат передаётся в headers. |
| Подписка на Stream срабатывает после ухода с экрана | В dispose() вызывать subscription.cancel(). |
| Тема не применяется | Проверить, что ThemeData передаётся в MaterialApp и виджеты используют Theme.of(context). |

---

## 5. Ссылки на документацию

- **Dart:** [dart.dev](https://dart.dev), [Effective Dart](https://dart.dev/guides/language/effective-dart).
- **Flutter:** [flutter.dev](https://flutter.dev), [docs.flutter.dev](https://docs.flutter.dev).
- **Пакеты:** [pub.dev](https://pub.dev) — поиск пакетов (http, shared_preferences, flutter_secure_storage и др.).

---

*Все тома учебника лежат в папке docs/tutorial/. Оглавление — docs/TUTORIAL_INDEX.md.*
