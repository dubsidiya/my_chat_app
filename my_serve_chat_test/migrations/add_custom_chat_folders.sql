-- Пользовательские папки чатов (до 5 на пользователя) + привязка chat_users.folder_id
-- Дата: 2026-02-20

-- 1) Таблица папок пользователя
CREATE TABLE IF NOT EXISTS chat_folders (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(50) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_chat_folders_user_id ON chat_folders(user_id);

-- 2) Привязка папки к чату для пользователя
ALTER TABLE chat_users
  ADD COLUMN IF NOT EXISTS folder_id INTEGER REFERENCES chat_folders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_chat_users_user_id_folder_id ON chat_users(user_id, folder_id);

-- 3) Best-effort миграция существующего chat_users.folder -> chat_folders + folder_id
-- Важно: используем только простые statements (без DO-block).
-- Предполагаем, что chat_users.folder уже существует (миграция add_chat_folders.sql).

INSERT INTO chat_folders (user_id, name)
SELECT DISTINCT
  cu.user_id,
  CASE
    WHEN lower(cu.folder) = 'work' THEN 'Работа'
    WHEN lower(cu.folder) = 'personal' THEN 'Личное'
    WHEN lower(cu.folder) = 'archive' THEN 'Архив'
    ELSE left(cu.folder, 50)
  END AS name
FROM chat_users cu
WHERE cu.folder IS NOT NULL AND btrim(cu.folder) <> ''
  AND NOT EXISTS (
    SELECT 1 FROM chat_folders cf
    WHERE cf.user_id = cu.user_id
      AND lower(cf.name) = lower(
        CASE
          WHEN lower(cu.folder) = 'work' THEN 'Работа'
          WHEN lower(cu.folder) = 'personal' THEN 'Личное'
          WHEN lower(cu.folder) = 'archive' THEN 'Архив'
          ELSE left(cu.folder, 50)
        END
      )
  );

UPDATE chat_users cu
SET folder_id = cf.id
FROM chat_folders cf
WHERE cu.user_id = cf.user_id
  AND cu.folder IS NOT NULL AND btrim(cu.folder) <> ''
  AND lower(cf.name) = lower(
    CASE
      WHEN lower(cu.folder) = 'work' THEN 'Работа'
      WHEN lower(cu.folder) = 'personal' THEN 'Личное'
      WHEN lower(cu.folder) = 'archive' THEN 'Архив'
      ELSE left(cu.folder, 50)
    END
  )
  AND cu.folder_id IS NULL;

