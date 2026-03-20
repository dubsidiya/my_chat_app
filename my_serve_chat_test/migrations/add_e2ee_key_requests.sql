-- Pending E2EE key requests for reliable offline/online delivery.

CREATE TABLE IF NOT EXISTS chat_key_requests (
  id SERIAL PRIMARY KEY,
  chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  requester_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key_version INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'pending', -- pending | fulfilled
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(chat_id, requester_user_id, key_version)
);

CREATE INDEX IF NOT EXISTS idx_ckr_chat_status ON chat_key_requests(chat_id, status);
CREATE INDEX IF NOT EXISTS idx_ckr_requester_status ON chat_key_requests(requester_user_id, status);
