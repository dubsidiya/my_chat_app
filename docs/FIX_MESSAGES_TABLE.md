# Исправление таблицы messages

## Проблема
В таблице `messages` колонка называется `sender_id`, а контроллеры ожидают `user_id`.

## Решение

### Вариант 1: Переименовать колонку (рекомендуется)

Выполните в Neon SQL Editor:

```sql
-- Переименовать колонку sender_id в user_id
ALTER TABLE messages RENAME COLUMN sender_id TO user_id;
```

### Вариант 2: Использовать автоматический скрипт

Выполните SQL из файла `fix_messages_table.sql` - он автоматически:
- Проверит, какая колонка существует
- Переименует `sender_id` в `user_id` (если есть)
- Или создаст `user_id` (если нет)

## Проверка

После выполнения проверьте структуру таблицы:

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'messages'
ORDER BY ordinal_position;
```

Должна быть колонка `user_id` типа `integer`.

## Важно

После переименования колонки:
1. ✅ Все существующие данные сохранятся
2. ✅ Контроллеры начнут работать корректно
3. ✅ Приложение сможет получать и отправлять сообщения

