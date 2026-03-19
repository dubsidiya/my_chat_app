-- Версия токена: при смене пароля или сбросе через админку увеличивается на 1.
-- JWT содержит tv (token version); при проверке сверяется с БД.
-- Все ранее выданные токены становятся недействительными после инкремента.
ALTER TABLE users ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 0;
