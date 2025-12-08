# Исправление ошибки BuildScope

## Проблема
Ошибка `BuildScope._debugAssertElementInScope` возникала из-за того, что `setState` вызывался после того, как виджет был удален из дерева виджетов.

## Что было исправлено:

### 1. Добавлены проверки `mounted` перед каждым `setState`

Во всех асинхронных методах теперь проверяется, что виджет все еще в дереве перед вызовом `setState`:

- ✅ `HomeScreen._loadChats()` - проверка `mounted` перед всеми `setState`
- ✅ `ChatScreen._loadMessages()` - проверка `mounted` перед всеми `setState`
- ✅ `ChatScreen._sendMessage()` - проверка `mounted` перед использованием `context`
- ✅ `LoginScreen._login()` - проверка `mounted` перед всеми `setState` и навигацией
- ✅ `RegisterScreen._register()` - проверка `mounted` перед всеми `setState` и навигацией

### 2. Исправлена обработка WebSocket

- ✅ Добавлена переменная `_webSocketSubscription` для хранения подписки
- ✅ Подписка отменяется в `dispose()` перед закрытием канала
- ✅ Добавлена проверка `mounted` в обработчике WebSocket сообщений
- ✅ Добавлена обработка ошибок парсинга JSON в WebSocket

### 3. Добавлен импорт `dart:async`

Для использования `StreamSubscription` в `ChatScreen`.

## Паттерн исправления:

**Было:**
```dart
Future<void> _someMethod() async {
  setState(() => _isLoading = true);
  try {
    final data = await _service.getData();
    setState(() => _data = data);
  } finally {
    setState(() => _isLoading = false);
  }
}
```

**Стало:**
```dart
Future<void> _someMethod() async {
  if (!mounted) return;
  setState(() => _isLoading = true);
  try {
    final data = await _service.getData();
    if (mounted) {
      setState(() => _data = data);
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}
```

## Результат:

- ✅ Больше не будет ошибок `BuildScope._debugAssertElementInScope`
- ✅ Приложение не будет падать при быстрой навигации между экранами
- ✅ WebSocket правильно закрывается при удалении виджета
- ✅ Все асинхронные операции безопасны

## Важно:

Всегда проверяйте `mounted` перед:
- Вызовом `setState`
- Использованием `context` (например, `Navigator.push`, `ScaffoldMessenger`)
- Любыми операциями, которые зависят от состояния виджета

Это стандартная практика в Flutter для предотвращения ошибок при работе с асинхронными операциями.

