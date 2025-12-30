-- Миграция: Добавление статусов сообщений (доставлено/прочитано)
-- Дата: 2025-01-29

-- Добавляем поля для отслеживания доставки и прочтения
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS edited_at TIMESTAMP;

-- Таблица для отслеживания прочтения сообщений участниками чата
-- Это нужно для групповых чатов, где нужно знать, кто именно прочитал
CREATE TABLE IF NOT EXISTS message_reads (
    id SERIAL PRIMARY KEY,
    message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    read_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(message_id, user_id)
);

-- Индексы для оптимизации запросов
CREATE INDEX IF NOT EXISTS idx_message_reads_message_id ON message_reads(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reads_user_id ON message_reads(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_delivered_at ON messages(delivered_at);
CREATE INDEX IF NOT EXISTS idx_messages_edited_at ON messages(edited_at);

-- Комментарии
COMMENT ON COLUMN messages.delivered_at IS 'Время доставки сообщения (устанавливается при получении через WebSocket)';
COMMENT ON COLUMN messages.edited_at IS 'Время последнего редактирования сообщения';
COMMENT ON TABLE message_reads IS 'Отслеживание прочтения сообщений участниками чата';

