-- Исправление текущей БД: добавление отсутствующей колонки is_group

-- Добавить колонку is_group в таблицу chats, если её нет
ALTER TABLE chats 
ADD COLUMN IF NOT EXISTS is_group BOOLEAN DEFAULT false;

-- Обновить существующие записи (если нужно)
-- UPDATE chats SET is_group = false WHERE is_group IS NULL;

