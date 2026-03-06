# Том 3. Flutter: виджеты и интерфейс

Третий том посвящён **интерфейсу во Flutter**: виджеты, дерево виджетов, состояние (State), компоновка (Row, Column, ListView), темы и форма ввода. Примеры по возможности взяты из проекта my_chat_app.

**Предполагается:** Том 1 (Dart основы), Том 2 (async/await, Future).

**Что дальше:** Том 4 — навигация между экранами.

---

## Оглавление тома 3

1. [Что такое Flutter и виджет](#1-что-такое-flutter-и-виджет)
2. [Дерево виджетов и BuildContext](#2-дерево-виджетов-и-buildcontext)
3. [StatelessWidget и StatefulWidget](#3-statelesswidget-и-statefulwidget)
4. [Состояние: setState и жизненный цикл](#4-состояние-setstate-и-жизненный-цикл)
5. [Компоновка: Row, Column, Expanded](#5-компоновка-row-column-expanded)
6. [Списки: ListView](#6-списки-listview)
7. [Тема и стили](#7-тема-и-стили)
8. [Форма ввода: TextField и контроллеры](#8-форма-ввода-textfield-и-контроллеры)
9. [Часто используемые виджеты](#9-часто-используемые-виджеты)
10. [Проверь себя](#10-проверь-себя)

---

## 1. Что такое Flutter и виджет

**Flutter** — фреймворк для построения интерфейсов. Один код собирается под iOS, Android и Web. Язык — **Dart**.

Во Flutter **всё есть виджет** (widget): кнопка, текст, отступ, экран, приложение. Интерфейс строится как **дерево виджетов**: у каждого виджета есть дочерние (children), у тех — свои дочерние, и так до мельчайших элементов. Flutter перерисовывает только те части дерева, у которых изменились данные или конфигурация.

---

## 2. Дерево виджетов и BuildContext

**Дерево виджетов** — иерархия: корень обычно **MaterialApp**, внутри — экран (**Scaffold**), в нём **AppBar**, **body** (например, Column или ListView), внутри — кнопки, текст, картинки.

**BuildContext** — объект, который передаётся в метод **build** виджета. Через него получают доступ к:
- **Theme.of(context)** — тема (цвета, шрифты);
- **Navigator.of(context)** — навигация (push/pop);
- **ScaffoldMessenger.of(context)** — показ SnackBar;
- **MediaQuery.of(context)** — размер экрана, отступы.

Пример из проекта: в экранах часто пишут `Theme.of(context).colorScheme`, `Navigator.push(context, ...)`.

---

## 3. StatelessWidget и StatefulWidget

### 3.1. StatelessWidget

Виджет **без внутреннего изменяемого состояния**. Всё, что он показывает, задаётся параметрами (и темой из context). При смене параметров виджет перестраивается родителем.

```dart
class MyTitle extends StatelessWidget {
  final String text;

  const MyTitle({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleLarge);
  }
}
```

В проекте: **EulaConsentScreen** — StatelessWidget (фиксированный текст и кнопка); **ChatInputBar** — StatelessWidget (получает controller и callbacks снаружи).

### 3.2. StatefulWidget

Виджет **с состоянием**: данные, которые могут меняться (список чатов, текст ошибки, флаг загрузки). Состояние хранится в отдельном объекте **State**. При вызове **setState** Flutter перестраивает виджет с новыми данными.

```dart
class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Счёт: $_count'),
        ElevatedButton(
          onPressed: () => setState(() => _count++),
          child: const Text('+1'),
        ),
      ],
    );
  }
}
```

В проекте: **LoginScreen**, **HomeScreen**, **ChatScreen** — StatefulWidget (списки, загрузка, ошибки, ввод).

---

## 4. Состояние: setState и жизненный цикл

### 4.1. setState

**setState** — метод класса **State**. В него передают функцию (часто лямбду), в которой меняют поля состояния. Flutter после этого заново вызывает **build** и перерисовывает виджет.

```dart
setState(() {
  _isLoading = false;
  _errorMessage = 'Не удалось загрузить';
});
```

После асинхронной операции перед setState обязательно проверять **mounted**:

```dart
final data = await fetchData();
if (!mounted) return;
setState(() => _data = data);
```

### 4.2. Жизненный цикл State

- **initState()** — вызывается один раз после создания State. Здесь подписываются на Stream, запускают загрузку, инициализируют контроллеры.
- **dispose()** — вызывается при удалении виджета. Здесь отменяют подписки, вызывают **controller.dispose()** у TextEditingController и т.п.

В проекте в **HomeScreen** в initState вызываются _loadChats(), _loadFolders(), _subscribeToNewMessages(); в dispose — _wsSubscription?.cancel(), _searchController.dispose().

---

## 5. Компоновка: Row, Column, Expanded

**Row** — дочерние виджеты в ряд по горизонтали. **Column** — по вертикали. У обоих есть параметры **mainAxisAlignment** (выравнивание по главной оси) и **crossAxisAlignment** (по поперечной).

```dart
Column(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    Text('Заголовок'),
    SizedBox(height: 16),
    Row(
      children: [
        Icon(Icons.star),
        SizedBox(width: 8),
        Text('Рейтинг'),
      ],
    ),
  ],
)
```

**Expanded** — ребёнок Row или Column занимает всё оставшееся место по главной оси. Удобно для кнопки «на всю ширину» или поля ввода рядом с иконкой.

В **ChatInputBar** Row содержит иконки и **Expanded(child: TextField(...))** — поле ввода растягивается.

---

## 6. Списки: ListView

**ListView** строит прокручиваемый список дочерних виджетов.

- **ListView(children: [...])** — все элементы в памяти. Подходит для коротких списков.
- **ListView.builder** — элементы создаются по мере прокрутки (itemCount, itemBuilder). Используется для длинных списков (чаты, сообщения).

```dart
ListView.builder(
  itemCount: _chats.length,
  itemBuilder: (context, index) {
    final chat = _chats[index];
    return ListTile(
      title: Text(chat.name),
      onTap: () => _openChat(chat),
    );
  },
)
```

В проекте список чатов на **HomeScreen** и список сообщений на **ChatScreen** строятся через ListView.builder (или ReorderableListView для чатов с перетаскиванием).

**ScrollController** — если нужно программно прокрутить список (например, к последнему сообщению в чате). Создают контроллер в State, передают в `ListView.builder(controller: _scrollController)`, в initState/dispose не забывают **dispose()**. Прокрутка: `_scrollController.jumpTo(offset)` или `animateTo`. В **ChatScreen** так прокручивают к низу после загрузки сообщений и после отправки своего.

---

## 7. Тема и стили

Единый вид задаётся **ThemeData**. В **main.dart** тема строится в методе **_buildTheme()**: **ColorScheme.dark** с цветами из **AppColors** (lib/theme/app_colors.dart). Задаются цвета фона, карточек, кнопок, полей ввода, SnackBar и т.д.

Виджеты берут цвета так:
- **Theme.of(context).colorScheme** — primary, surface, onSurface, error и др.;
- напрямую **AppColors.primary**, **AppColors.primaryGlow** и т.д.

Пример из проекта:
```dart
const scheme = ColorScheme.dark(
  primary: AppColors.primary,
  surface: AppColors.surfaceDark,
  onSurface: AppColors.onSurfaceDark,
);
return ThemeData(
  brightness: Brightness.dark,
  colorScheme: scheme,
  scaffoldBackgroundColor: surface,
  ...
);
```

---

## 8. Форма ввода: TextField и контроллеры

**TextField** — поле ввода текста. Чтобы читать и задавать текст программно, используют **TextEditingController**.

```dart
final _controller = TextEditingController();

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

TextField(
  controller: _controller,
  decoration: InputDecoration(
    labelText: 'Логин',
    border: OutlineInputBorder(),
  ),
  onChanged: (value) => setState(() => _input = value),
)
```

Получить текст: **\_controller.text**. Очистить: **\_controller.clear()**.

В проекте на **LoginScreen** используются _usernameController и _passwordController; в **ChatInputBar** контроллер передаётся снаружи (управление в родителе).

---

## 9. Часто используемые виджеты

| Виджет | Назначение |
|--------|------------|
| **Scaffold** | Каркас экрана: AppBar, body, floatingActionButton, drawer. |
| **AppBar** | Верхняя панель: заголовок, кнопки, leading. |
| **Card** | Карточка с тенью и скруглением. В проекте — карточка чата в списке. |
| **ListTile** | Строка с leading/trailing и title/subtitle. |
| **ElevatedButton, TextButton, OutlinedButton** | Кнопки с разным стилем. |
| **CircularProgressIndicator** | Круговой индикатор загрузки. |
| **SnackBar** | Всплывающее сообщение внизу (через ScaffoldMessenger.of(context).showSnackBar). |
| **Dialog, AlertDialog** | Диалоговое окно. |
| **SafeArea** | Отступ от выреза экрана и системных панелей. |

**Картинки по URL.** Для отображения изображения по ссылке используют **Image.network(url)**. В проекте чаще **CachedNetworkImage** (пакет cached_network_image): кэширует загруженные картинки и показывает плейсхолдер пока идёт загрузка — удобно для аватарок и превью вложений в чате (ChatMessageTile, HomeScreen, ProfileScreen).

---

## 10. Проверь себя

1. В чём разница между StatelessWidget и StatefulWidget? Приведи по одному примеру из проекта.
2. Зачем вызывать controller.dispose() в State.dispose?
3. Собери экран: Column с заголовком Text, под ним TextField с контроллером, под ним ElevatedButton «Отправить», по нажатию вывести текст поля в SnackBar.
4. Где в проекте задаётся тёмная тема и основные цвета? Открой lib/theme/app_colors.dart и lib/main.dart (_buildTheme).

**Что дальше:** Том 4 — навигация, передача данных между экранами, диалоги.

---

*Том 3 входит в полный учебник. План — docs/TUTORIAL_INDEX.md.*
