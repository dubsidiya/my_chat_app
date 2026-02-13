-- FCM (Firebase Cloud Messaging) токен для push-уведомлений на мобильных и веб
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT;
COMMENT ON COLUMN users.fcm_token IS 'Токен Firebase Cloud Messaging для отправки push-уведомлений';
