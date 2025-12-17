-- SQL скрипт для оптимизации пагинации сообщений
-- Создает индексы для ускорения запросов

-- Индекс для быстрого поиска сообщений по чату и времени создания
-- Используется для offset-based пагинации
CREATE INDEX IF NOT EXISTS idx_messages_chat_created 
ON messages(chat_id, created_at DESC);

-- Индекс для cursor-based пагинации
-- Используется для загрузки сообщений до определенного ID
CREATE INDEX IF NOT EXISTS idx_messages_chat_id 
ON messages(chat_id, id DESC);

-- Композитный индекс для оптимизации JOIN с users
-- Ускоряет получение email отправителя
CREATE INDEX IF NOT EXISTS idx_messages_user_id 
ON messages(user_id);

-- Индекс для быстрого подсчета сообщений в чате
-- Используется для определения totalCount
-- (chat_id уже индексирован выше, но можно добавить для COUNT)

-- Проверка индексов
SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'messages'
ORDER BY indexname;

