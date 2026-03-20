-- E2EE key versioning foundation.
-- Safe, additive migration with compatibility defaults.

-- 1) Current key version on chat (used as default read/write version)
ALTER TABLE chats
ADD COLUMN IF NOT EXISTS current_key_version INTEGER NOT NULL DEFAULT 1;

-- 2) Versioned key envelopes per user
ALTER TABLE chat_keys
ADD COLUMN IF NOT EXISTS key_version INTEGER NOT NULL DEFAULT 1;

-- 3) Message version marker (for future rotation-aware decrypt)
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS key_version INTEGER NOT NULL DEFAULT 1;

-- 4) Replace old unique(chat_id, user_id) with versioned unique constraint
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE table_name = 'chat_keys'
      AND constraint_name = 'chat_keys_chat_id_user_id_key'
  ) THEN
    ALTER TABLE chat_keys DROP CONSTRAINT chat_keys_chat_id_user_id_key;
  END IF;
END $$;

ALTER TABLE chat_keys
ADD CONSTRAINT chat_keys_chat_id_user_id_key_version_key
UNIQUE (chat_id, user_id, key_version);

-- 5) Helpful indexes for key lookup/versioned history
CREATE INDEX IF NOT EXISTS idx_chat_keys_chat_version ON chat_keys(chat_id, key_version);
CREATE INDEX IF NOT EXISTS idx_messages_chat_key_version_created_at ON messages(chat_id, key_version, created_at);
