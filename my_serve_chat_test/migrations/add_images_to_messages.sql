-- Добавление поддержки изображений в сообщения
-- Запустите этот скрипт в вашей PostgreSQL базе данных

-- Добавляем поле для URL изображения
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Добавляем поле для типа сообщения (text, image, или оба)
ALTER TABLE messages 
ADD COLUMN IF NOT EXISTS message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'text_image'));

-- Индекс для поиска сообщений с изображениями (опционально)
CREATE INDEX IF NOT EXISTS idx_messages_image_url ON messages(image_url) WHERE image_url IS NOT NULL;

-- Комментарий к изменениям
COMMENT ON COLUMN messages.image_url IS 'URL изображения, прикрепленного к сообщению';
COMMENT ON COLUMN messages.message_type IS 'Тип сообщения: text, image, или text_image';

