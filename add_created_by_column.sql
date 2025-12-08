-- Добавление колонки created_by в таблицу chats
-- Выполните этот SQL в Neon SQL Editor

-- Добавляем колонку created_by
ALTER TABLE chats ADD COLUMN IF NOT EXISTS created_by INTEGER REFERENCES users(id) ON DELETE SET NULL;

-- Обновляем существующие чаты: устанавливаем created_by как первого участника
UPDATE chats c
SET created_by = (
  SELECT cu.user_id 
  FROM chat_users cu 
  WHERE cu.chat_id = c.id 
  ORDER BY cu.chat_id 
  LIMIT 1
)
WHERE created_by IS NULL;

-- Проверяем результат
SELECT c.id, c.name, c.created_by, u.email as creator_email
FROM chats c
LEFT JOIN users u ON c.created_by = u.id;

