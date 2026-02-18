-- Аватар пользователя (URL после загрузки в облако)
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;
