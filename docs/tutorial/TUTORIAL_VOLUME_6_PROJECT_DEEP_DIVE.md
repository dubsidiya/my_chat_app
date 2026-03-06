# Том 6. Проект my_chat_app: разбор целиком

Шестой том — **глубокий разбор проекта** my_chat_app: точка входа main.dart, цепочка экранов, сервисы и модели, типичные задачи (добавить поле, изменить текст, подключить новый API).

**Предполагается:** Тома 1–5 пройдены.

**Что дальше:** Том 7 — практические задачи и мини-проекты.

---

## Оглавление

1. [Точка входа: main.dart](#1-точка-входа-maindart)
2. [Цепочка экранов от запуска](#2-цепочка-экранов-от-запуска)
3. [Экраны: кто за что отвечает](#3-экраны-кто-за-что-отвечает)
4. [Сервисы и вызовы](#4-сервисы-и-вызовы)
5. [Модели данных](#5-модели-данных)
6. [Типичная задача: добавить поле на экран](#6-типичная-задача-добавить-поле-на-экран)
7. [Типичная задача: изменить текст или кнопку](#7-типичная-задача-изменить-текст-или-кнопку)
8. [Типичная задача: новый API-метод](#8-типичная-задача-новый-api-метод)
9. [Проверь себя](#9-проверь-себя)

---

## 1. Точка входа: main.dart

В **lib/main.dart**:
- **main()** — настройка глобальной обработки ошибок (FlutterError.onError, runZonedGuarded), инициализация (WidgetsFlutterBinding, форматирование дат, LocalMessagesService, PushNotificationService), затем **runApp(const MyApp())**.
- **MyApp** — StatefulWidget. В **build** возвращается **MaterialApp** с темой (**_buildTheme**) и **home**: не готовый виджет, а **FutureBuilder**. Future загружает данные пользователя и флаг EULA из StorageService; по результату показывается экран загрузки, **LoginScreen**, **EulaConsentScreen** или **MainTabsScreen**. Так при наличии токена пользователь сразу попадает в приложение без повторного ввода логина.

---

## 2. Цепочка экранов от запуска

- Нет токена / нет пользователя → **LoginScreen**.
- Есть токен, EULA не принята → **EulaConsentScreen** (после «Принимаю» → MainTabsScreen).
- Есть токен и EULA → **MainTabsScreen** (вкладки: чаты HomeScreen, и др.).
- С HomeScreen по тапу на чат → **ChatScreen** (chatId, chatName передаются в конструктор).
- Из меню/профиля — **ProfileScreen**, смена пароля, удаление аккаунта, выход (pushAndRemoveUntil на LoginScreen).

---

## 3. Экраны: кто за что отвечает

| Экран | Файл | Назначение |
|-------|------|------------|
| LoginScreen | login_screen.dart | Форма входа, вызов AuthService.loginUser, при успехе — pushReplacement на EulaConsent или MainTabsScreen. |
| EulaConsentScreen | eula_consent_screen.dart | Текст условий, кнопка «Принимаю»; сохранение EULA через StorageService, переход на MainTabsScreen. |
| MainTabsScreen | main_tabs_screen.dart | Нижние вкладки; одна из вкладок — HomeScreen с чатами. |
| HomeScreen | home_screen.dart | Список чатов (ChatsService.fetchChats), поиск, папки, создание чата, подписка на WebSocket, переход в ChatScreen и ProfileScreen. |
| ChatScreen | chat_screen.dart | Сообщения (MessagesService), ввод (ChatInputBar), отправка, WebSocket для новых сообщений. |
| ProfileScreen | profile_screen.dart | Профиль, смена пароля, удаление аккаунта, выход. |
| RegisterScreen | register_screen.dart | Регистрация: форма (email/пароль и др.), вызов AuthService.register, при успехе — переход на логин или в приложение. |

**Переиспользуемые виджеты** (lib/widgets/): **ChatMessageTile** — одна строка сообщения в чате; **ChatInputBar** — поле ввода и кнопки отправки; **LinkPreviewCard** — превью ссылки; аватарки и превью картинок часто рисуют через **CachedNetworkImage**.

---

## 4. Сервисы и вызовы

- **AuthService** — вызывается из LoginScreen, RegisterScreen, ProfileScreen (login, register, changePassword, deleteAccount, updateProfile, fetchMe).
- **StorageService** — вызывается из main (getUserData, getEulaAccepted), из AuthService (saveUserData, clearUserData), из HomeScreen (getChatOrder, saveChatOrder), из экранов профиля и EULA.
- **ChatsService** — из HomeScreen (fetchChats, createChat, deleteChat, fetchFolders, setChatFolderId и т.д.).
- **MessagesService** — из ChatScreen (fetchMessagesPaginated, отправка сообщений).
- **WebSocketService** — connectIfNeeded в main (после загрузки) и в didChangeAppLifecycleState (resumed); подписка в HomeScreen и ChatScreen.

---

## 5. Модели данных

- **Chat** (lib/models/chat.dart) — id, name, isGroup, folderId, lastMessage*, unreadCount; fromJson.
- **Message** (lib/models/message.dart) — id, chatId, content, senderEmail, createdAt, вложения, реакции, статус; fromJson, toJson.
- **User** (lib/models/user.dart) — id, email; fromJson.

Данные с API приходят в JSON; в сервисах вызывается jsonDecode и затем Model.fromJson (или цикл по списку).

---

## 6. Типичная задача: добавить поле на экран

1. Определить, какой экран и какое состояние (переменная в State или параметр виджета).
2. Добавить поле в State (например, `String? _newField`) или в конструктор экрана.
3. В **build** добавить виджет (Text, TextField, и т.д.), при необходимости обновлять значение через setState или контроллер.
4. Если данные приходят с API — в сервисе распарсить новое поле (модель или Map), сохранить в состояние и вызвать setState (после проверки mounted).

---

## 7. Типичная задача: изменить текст или кнопку

1. Открыть нужный экран/виджет в lib/screens/ или lib/widgets/.
2. Найти строку с текстом (например, `'Войти'`, `'Отправить'`) или виджет кнопки.
3. Изменить строку или подпись кнопки; при необходимости обновить стиль (Theme, AppColors).

---

## 8. Типичная задача: новый API-метод

1. Выбрать сервис (AuthService, ChatsService, MessagesService).
2. Добавить метод `Future<...> newMethod(...) async`: сформировать URL (baseUrl + путь), вызвать _getAuthHeaders(), выполнить http.get/post/put/delete с body при необходимости.
3. По statusCode обработать успех и ошибки (throw Exception с текстом для пользователя).
4. Распарсить response.body (jsonDecode), при необходимости создать модель с fromJson.
5. На экране вызвать метод в async-функции, в try/catch обновить состояние или показать SnackBar при ошибке.

---

## 9. Проверь себя

1. Опиши путь от нажатия «Войти» до появления списка чатов (какие экраны и сервисы задействованы).
2. Где в коде решается, показать LoginScreen или MainTabsScreen при запуске?
3. Добавь на экран логина под кнопкой «Войти» текст-подсказку «Забыли пароль?» (пока без перехода).

**Куда развивать проект дальше.** Идеи фич и доработок (светлая тема, восстановление пароля, архив чатов, глобальный поиск и др.) собраны в **docs/FEATURES_IDEAS.md**. После прохождения учебника удобно выбрать оттуда задачу по уровню сложности и реализовать её в my_chat_app.

**Что дальше:** Том 7 — практика: задачи и мини-проекты.

---

*План томов — docs/TUTORIAL_INDEX.md. Тома лежат в docs/tutorial/.*
