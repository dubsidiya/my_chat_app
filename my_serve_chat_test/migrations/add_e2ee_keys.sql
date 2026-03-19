-- E2EE: публичный ключ X25519 пользователя (base64, ~44 символа)
ALTER TABLE users ADD COLUMN IF NOT EXISTS public_key TEXT;

-- E2EE: зашифрованные ключи чатов (для каждого участника — своя копия AES-ключа чата,
-- зашифрованная общим секретом X25519 между создателем ключа и участником).
CREATE TABLE IF NOT EXISTS chat_keys (
  id SERIAL PRIMARY KEY,
  chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  encrypted_key TEXT NOT NULL,       -- base64(AES-GCM encrypted chat key)
  sender_public_key TEXT NOT NULL,   -- public key отправителя для DH (base64)
  nonce TEXT NOT NULL,               -- base64(nonce/iv для расшифровки)
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(chat_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_keys_chat_id ON chat_keys(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_keys_user_id ON chat_keys(user_id);
