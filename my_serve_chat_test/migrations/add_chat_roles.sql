-- Миграция: Роли в чатах (owner/admin/member)
-- Дата: 2026-01-21

-- Добавляем роль участника в chat_users
ALTER TABLE chat_users
ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'member';

-- Ограничение на значения роли
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chat_users_role_check'
  ) THEN
    ALTER TABLE chat_users
      ADD CONSTRAINT chat_users_role_check
      CHECK (role IN ('owner', 'admin', 'member'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_chat_users_chat_id_role ON chat_users(chat_id, role);

-- Назначаем owner всем создателям чатов (best-effort)
UPDATE chat_users cu
SET role = 'owner'
FROM chats c
WHERE cu.chat_id = c.id
  AND cu.user_id = c.created_by
  AND cu.role <> 'owner';

