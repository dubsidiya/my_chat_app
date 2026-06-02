-- Скрытие сообщений «только у меня» (личные чаты, как в Telegram)
CREATE TABLE IF NOT EXISTS message_user_deletions (
  message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_user_deletions_user_id
  ON message_user_deletions(user_id);
