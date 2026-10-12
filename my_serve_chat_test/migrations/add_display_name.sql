-- Display name used by registration, profile, chats and member lists.
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR(255);
