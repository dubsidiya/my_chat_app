-- Миграция: Добавление поддержки файлов (attachments) в сообщения
-- Дата: 2026-01-21

-- ✅ Колонки для файла
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS file_url TEXT;

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS file_name TEXT;

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS file_size BIGINT;

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS file_mime TEXT;

-- ✅ Расширяем message_type (добавляем file/text_file)
-- В разных БД имя constraint может отличаться, поэтому ищем и удаляем check по message_type
DO $$
DECLARE
  c_name text;
BEGIN
  SELECT c.conname INTO c_name
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  WHERE t.relname = 'messages'
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%message_type%'
  LIMIT 1;

  IF c_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE messages DROP CONSTRAINT %I', c_name);
  END IF;
END $$;

ALTER TABLE messages
  ADD CONSTRAINT messages_message_type_check
  CHECK (message_type IN ('text', 'image', 'text_image', 'file', 'text_file'));

-- Индексы (опционально)
CREATE INDEX IF NOT EXISTS idx_messages_file_url ON messages(file_url) WHERE file_url IS NOT NULL;

COMMENT ON COLUMN messages.file_url IS 'Публичный URL вложенного файла (attachment)';
COMMENT ON COLUMN messages.file_name IS 'Оригинальное имя файла (для отображения)';
COMMENT ON COLUMN messages.file_size IS 'Размер файла в байтах';
COMMENT ON COLUMN messages.file_mime IS 'MIME-тип файла';

