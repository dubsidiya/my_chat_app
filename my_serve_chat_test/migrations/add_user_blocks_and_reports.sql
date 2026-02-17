-- Блокировки пользователей (Guideline 1.2): кто кого заблокировал
CREATE TABLE IF NOT EXISTS user_blocks (
    blocker_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON user_blocks(blocker_id);

-- Жалобы на контент (сообщения)
CREATE TABLE IF NOT EXISTS content_reports (
    id SERIAL PRIMARY KEY,
    message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    reporter_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(message_id, reporter_id)
);
CREATE INDEX IF NOT EXISTS idx_content_reports_message ON content_reports(message_id);
CREATE INDEX IF NOT EXISTS idx_content_reports_reporter ON content_reports(reporter_id);

COMMENT ON TABLE user_blocks IS 'Блокировки: blocker не видит сообщения blocked и не может с ним общаться';
COMMENT ON TABLE content_reports IS 'Жалобы на сообщения для модерации';
