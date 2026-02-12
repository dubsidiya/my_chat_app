-- Удаление таблицы и колонки, связанных со сбросом пароля по email
-- Сброс пароля теперь только через админа

DROP TABLE IF EXISTS password_reset_tokens;
ALTER TABLE users DROP COLUMN IF EXISTS recovery_email;
