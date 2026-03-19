-- E2EE: публичный ключ X25519 пользователя (base64, ~44 символа)
ALTER TABLE users ADD COLUMN IF NOT EXISTS public_key TEXT;

-- E2EE: бэкап приватного ключа, зашифрованный паролем пользователя (PBKDF2 + AES-GCM).
-- Позволяет восстановить ключи при смене устройства / переустановке.
ALTER TABLE users ADD COLUMN IF NOT EXISTS encrypted_key_backup TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS key_backup_salt TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS key_backup_nonce TEXT;

-- E2EE: зашифрованные ключи чатов (для каждого участника — своя копия AES-ключа чата,
-- зашифрованная общим секретом X25519 между создателем ключа и участником).
CREATE TABLE IF NOT EXISTS chat_keys (
  id SERIAL PRIMARY KEY,
  chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  encrypted_key TEXT NOT NULL,
  sender_public_key TEXT NOT NULL,
  nonce TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(chat_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_keys_chat_id ON chat_keys(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_keys_user_id ON chat_keys(user_id);
