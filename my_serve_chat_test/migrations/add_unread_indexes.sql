-- Индексы для списка чатов (last_message + unread_count)
-- Дата: 2026-01-19
--
-- Примечание: файл миграции добавлен для ускорения запросов.
-- Примените его вручную к PostgreSQL (или через ваш механизм миграций).

-- Быстрый доступ к сообщениям чата по убыванию id
CREATE INDEX IF NOT EXISTS idx_messages_chat_id_id_desc ON messages (chat_id, id DESC);

-- Быстрый lookup прочтений конкретного пользователя
CREATE INDEX IF NOT EXISTS idx_message_reads_user_message ON message_reads (user_id, message_id);

