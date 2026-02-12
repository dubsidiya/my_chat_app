-- Email для восстановления пароля (отправка кода только на почту)
ALTER TABLE users ADD COLUMN IF NOT EXISTS recovery_email VARCHAR(255);

COMMENT ON COLUMN users.recovery_email IS 'Email для отправки кода сброса пароля';
