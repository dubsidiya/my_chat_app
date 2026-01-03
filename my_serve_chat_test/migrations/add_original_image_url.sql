-- Миграция: Добавление колонки original_image_url в таблицу messages
-- Дата: 2025-01-30

-- ✅ Добавляем колонку для хранения URL оригинального изображения
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS original_image_url TEXT;

-- Комментарий
COMMENT ON COLUMN messages.original_image_url IS 'URL оригинального (несжатого) изображения в облачном хранилище';

