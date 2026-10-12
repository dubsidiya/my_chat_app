-- Chat type used by direct-chat, group-chat and call authorization flows.
-- Existing chats created before this migration are direct chats by default.
ALTER TABLE chats
ADD COLUMN IF NOT EXISTS is_group BOOLEAN NOT NULL DEFAULT false;
