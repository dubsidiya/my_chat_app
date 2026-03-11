# Миграция: FCM-токен для push-уведомлений

Применить **один раз** к вашей базе PostgreSQL (например: консоль ВМ в Яндекс Облаке, psql, или Render → Shell).

## Файл миграции

**`add_fcm_token.sql`** — добавляет колонку `fcm_token` в таблицу `users`.

## Как применить

### Вариант 1: через psql (локально или на сервере)

```bash
cd my_serve_chat_test
psql "$DATABASE_URL" -f migrations/add_fcm_token.sql
```

(Подставьте свой `DATABASE_URL` или экспортируйте переменную из `.env`.)

### Вариант 2: скопировать SQL и выполнить в консоли БД

Откройте консоль вашей БД (Яндекс Облако, Render, Supabase и т.д.) или любой клиент к вашей PostgreSQL и выполните:

```sql
-- FCM (Firebase Cloud Messaging) токен для push-уведомлений на мобильных и веб
ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT;
COMMENT ON COLUMN users.fcm_token IS 'Токен Firebase Cloud Messaging для отправки push-уведомлений';
```

### Проверка

После применения в таблице `users` должна появиться колонка `fcm_token` (тип `TEXT`, может быть `NULL`). Повторный запуск миграции безопасен (`IF NOT EXISTS`).
