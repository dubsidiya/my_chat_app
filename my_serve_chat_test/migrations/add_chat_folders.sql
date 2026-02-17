-- Папки/метки чатов для пользователя: Работа, Личное, Архив
-- folder хранится в chat_users (у каждого пользователя своя метка для чата)
ALTER TABLE chat_users
  ADD COLUMN IF NOT EXISTS folder VARCHAR(50) DEFAULT NULL;

COMMENT ON COLUMN chat_users.folder IS 'Метка чата для пользователя: work, personal, archive или NULL (без папки)';

CREATE INDEX IF NOT EXISTS idx_chat_users_user_id_folder ON chat_users(user_id, folder);
