-- Миграция: Добавление функций для сообщений (ответы, пересылка, закрепление, реакции)
-- Дата: 2025-01-29

-- ✅ Поле для ответа на сообщение (reply_to)
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS reply_to_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL;

-- ✅ Таблица для пересылки сообщений (чтобы знать, откуда переслано)
CREATE TABLE IF NOT EXISTS message_forwards (
    id SERIAL PRIMARY KEY,
    message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    original_chat_id INTEGER REFERENCES chats(id) ON DELETE SET NULL,
    original_message_id INTEGER, -- ID сообщения в оригинальном чате
    forwarded_by INTEGER REFERENCES users(id) ON DELETE CASCADE,
    forwarded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ✅ Таблица для закрепленных сообщений
CREATE TABLE IF NOT EXISTS pinned_messages (
    id SERIAL PRIMARY KEY,
    chat_id INTEGER REFERENCES chats(id) ON DELETE CASCADE,
    message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    pinned_by INTEGER REFERENCES users(id) ON DELETE CASCADE,
    pinned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(chat_id, message_id)
);

-- ✅ Таблица для реакций на сообщения
CREATE TABLE IF NOT EXISTS message_reactions (
    id SERIAL PRIMARY KEY,
    message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    reaction VARCHAR(10) NOT NULL, -- Эмодзи реакции (👍, ❤️, 😂 и т.д.)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(message_id, user_id, reaction) -- Один пользователь может поставить одну реакцию
);

-- ✅ Таблица для шаблонов сообщений
CREATE TABLE IF NOT EXISTS message_templates (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ✅ Таблица для геолокации в сообщениях
CREATE TABLE IF NOT EXISTS message_locations (
    id SERIAL PRIMARY KEY,
    message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    address TEXT, -- Адрес (опционально, можно получить через геокодинг)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для оптимизации
CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON messages(reply_to_message_id);
CREATE INDEX IF NOT EXISTS idx_message_forwards_message_id ON message_forwards(message_id);
CREATE INDEX IF NOT EXISTS idx_pinned_messages_chat_id ON pinned_messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_pinned_messages_message_id ON pinned_messages(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id ON message_reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_message_reactions_user_id ON message_reactions(user_id);
CREATE INDEX IF NOT EXISTS idx_message_templates_user_id ON message_templates(user_id);
CREATE INDEX IF NOT EXISTS idx_message_locations_message_id ON message_locations(message_id);

-- Комментарии
COMMENT ON COLUMN messages.reply_to_message_id IS 'ID сообщения, на которое отвечают';
COMMENT ON TABLE message_forwards IS 'Информация о пересылке сообщений';
COMMENT ON TABLE pinned_messages IS 'Закрепленные сообщения в чатах';
COMMENT ON TABLE message_reactions IS 'Реакции (эмодзи) на сообщения';
COMMENT ON TABLE message_templates IS 'Шаблоны быстрых ответов';
COMMENT ON TABLE message_locations IS 'Геолокация в сообщениях';

