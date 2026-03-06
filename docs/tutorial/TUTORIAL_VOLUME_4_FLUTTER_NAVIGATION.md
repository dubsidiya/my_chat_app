# Том 4. Flutter: навигация и диалоги

Четвёртый том — **навигация** между экранами: как открывать новый экран, как передавать данные, как возвращаться назад. Плюс **диалоги**, **нижние панели** (bottom sheet) и кратко — **именованные маршруты**.

**Предполагается:** Том 3 (виджеты, State, Scaffold).

**Что дальше:** Том 5 — сеть, API, хранилище, WebSocket.

---

## Оглавление тома 4

1. [Стек экранов и Navigator](#1-стек-экранов-и-navigator)
2. [Открытие экрана: push](#2-открытие-экрана-push)
3. [Возврат: pop и результат](#3-возврат-pop-и-результат)
4. [Передача данных между экранами](#4-передача-данных-между-экранами)
5. [pushReplacement и pushAndRemoveUntil](#5-pushreplacement-и-pushandremoveuntil)
6. [Диалоги: AlertDialog и showDialog](#6-диалоги-alertdialog-и-showdialog)
7. [Нижняя панель: showModalBottomSheet](#7-нижняя-панель-showmodalbottomsheet)
8. [Именованные маршруты (кратко)](#8-именованные-маршруты-кратко)
9. [Проверь себя](#9-проверь-себя)

---

## 1. Стек экранов и Navigator

Навигация во Flutter устроена как **стек**: текущий экран — верхний. **push** — положить новый экран сверху (мы переходим «вперёд»). **pop** — убрать верхний экран (мы возвращаемся «назад»).

**Navigator** — виджет, который хранит этот стек. Обычно один на всё приложение, создаётся внутри **MaterialApp**. Доступ: **Navigator.of(context)** или коротко **Navigator** в контексте экрана внутри MaterialApp.

---

## 2. Открытие экрана: push

**Navigator.push** — открыть новый экран поверх текущего. Передаём **context** и **Route**. Чаще всего используют **MaterialPageRoute** с **builder**, который возвращает виджет экрана.

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => ChatScreen(
      chatId: chat.id,
      chatName: chat.name,
    ),
  ),
);
```

После push пользователь видит новый экран; кнопка «назад» или системный жест возврата вызывают **pop**.

В проекте: переход из списка чатов в экран чата в **HomeScreen** (_openChat) — так и устроен: push с **ChatScreen**, в конструктор передаются **chatId**, **chatName**, **userId** и др.

---

## 3. Возврат: pop и результат

**Navigator.pop(context)** — закрыть текущий экран и вернуться к предыдущему.

Можно вернуть **результат** на предыдущий экран:

```dart
// на текущем экране (например, выбора варианта):
Navigator.pop(context, 'выбранный вариант');

// на предыдущем экране — push возвращает Future, который завершится с результатом при pop:
final result = await Navigator.push<String>(context, MaterialPageRoute(...));
if (result != null) {
  print('Выбрано: $result');
}
```

В проекте: после возврата с **ChatScreen** на **HomeScreen** вызывается **\_loadChats()** через **.then((_) => _loadChats())**, чтобы обновить список чатов.

---

## 4. Передача данных между экранами

Данные на новый экран передаются **через конструктор** виджета экрана. Никакой «глобальной переменной» не нужно: всё явно.

```dart
// Открывающий экран:
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ProfileScreen(
      userId: userId,
      userName: userName,
    ),
  ),
);

// ProfileScreen:
class ProfileScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const ProfileScreen({super.key, required this.userId, required this.userName});
  ...
}
```

Обратно данные передаются через **pop(context, result)** и **await Navigator.push(...)** — см. выше.

В проекте так передаются **userId**, **userEmail**, **chatId**, **chatName**, **isGroup** и т.д. между **HomeScreen**, **ChatScreen**, **ProfileScreen**, **EulaConsentScreen**, **MainTabsScreen**.

---

## 5. pushReplacement и pushAndRemoveUntil

**Navigator.pushReplacement** — заменить текущий экран новым. Предыдущий экран убирается из стека, «назад» вернётся уже к тому, что был под ним. Используется, например, после успешного входа: экран логина заменяется на главный, чтобы нельзя было вернуться на логин кнопкой «назад».

```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(builder: (_) => MainTabsScreen(...)),
);
```

В **LoginScreen** после успешного входа вызывается именно **pushReplacement** с **MainTabsScreen** или **EulaConsentScreen**.

**Navigator.pushAndRemoveUntil** — положить новый экран и убрать все предыдущие до условия. Типичный случай: выход из аккаунта — на экран входа и очистка всего стека.

```dart
Navigator.pushAndRemoveUntil(
  context,
  MaterialPageRoute(builder: (_) => const LoginScreen()),
  (route) => false,  // удалить все маршруты
);
```

В проекте так делают при выходе (**HomeScreen** _logout) и при удалении аккаунта.

---

## 6. Диалоги: AlertDialog и showDialog

**showDialog** — показать модальное окно поверх экрана. Возвращает **Future**, который завершится значением, переданным в **Navigator.pop(context, значение)** при закрытии диалога.

```dart
final confirmed = await showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Подтверждение'),
    content: const Text('Вы уверены?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Отмена'),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Да'),
      ),
    ],
  ),
);
if (confirmed == true) {
  // пользователь нажал «Да»
}
```

В проекте так устроены диалог выхода («Выйти из аккаунта?»), подтверждение удаления чата, диалог смены пароля, удаления аккаунта и т.д.

Для диалога с вводом текста в **content** кладут **TextField** с контроллером и по кнопке «ОК» делают **Navigator.pop(context, controller.text)**.

---

## 7. Нижняя панель: showModalBottomSheet

**showModalBottomSheet** — панель, выезжающая снизу (например, выбор варианта или форма). Не перекрывает весь экран, как диалог; часто с «ручкой» для смахивания вниз.

```dart
final result = await showModalBottomSheet<String>(
  context: context,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(title: const Text('Вариант 1'), onTap: () => Navigator.pop(context, '1')),
        ListTile(title: const Text('Вариант 2'), onTap: () => Navigator.pop(context, '2')),
      ],
    ),
  ),
);
```

В проекте так показываются выбор папки для чата (_showChatFolderPicker), управление папками (_manageFoldersFlow), главное меню (_showMainMenu) на **HomeScreen**.

---

## 8. Именованные маршруты (кратко)

Вместо **MaterialPageRoute(builder: ...)** можно зарегистрировать маршруты по имени в **MaterialApp**:

```dart
MaterialApp(
  routes: {
    '/': (context) => HomeScreen(),
    '/profile': (context) => ProfileScreen(...),
  },
);
```

Переход: **Navigator.pushNamed(context, '/profile')**. Для передачи аргументов используют **arguments** и **ModalRoute.of(context).settings.arguments**. В проекте my_chat_app в текущей версии в основном используются явные **MaterialPageRoute** с конструкторами — так проще передавать много параметров. Именованные маршруты удобны при большом количестве экранов и единой точке конфигурации.

---

## 9. Проверь себя

1. Чем отличается push от pushReplacement? Когда уместно каждое?
2. Как с экрана A передать на экран B строку `userId` и как вернуть с B на A результат выбора (например, bool)?
3. Найди в проекте один showDialog и один showModalBottomSheet. Что возвращают при закрытии?
4. Зачем при выходе из аккаунта использовать pushAndRemoveUntil, а не просто push на LoginScreen?

**Что дальше:** Том 5 — HTTP-запросы, API, хранилище (SharedPreferences, secure storage), WebSocket.

---

*Том 4 входит в полный учебник. План — docs/TUTORIAL_INDEX.md.*
