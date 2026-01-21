-- Миграция: Инвайт-ссылки в чат (chat_invites)
-- Дата: 2026-01-21

CREATE TABLE IF NOT EXISTS chat_invites (
  id SERIAL PRIMARY KEY,
  chat_id INTEGER REFERENCES chats(id) ON DELETE CASCADE,
  code TEXT NOT NULL UNIQUE,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  expires_at TIMESTAMP NULL,
  max_uses INTEGER NULL,
  use_count INTEGER NOT NULL DEFAULT 0,
  revoked BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_chat_invites_chat_id ON chat_invites(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_invites_code ON chat_invites(code);
CREATE INDEX IF NOT EXISTS idx_chat_invites_expires_at ON chat_invites(expires_at);

