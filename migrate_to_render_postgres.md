# Перенос БД на Render PostgreSQL

## Преимущества Render PostgreSQL
- ✅ Встроенная интеграция с Render сервисами
- ✅ Автоматические бэкапы
- ✅ Простая настройка
- ✅ Нет проблем с IPv6/IPv4

## Шаг 1: Создайте PostgreSQL на Render

1. Зайдите на https://dashboard.render.com
2. Нажмите **"New +"** → **"PostgreSQL"**
3. Заполните форму:
   - **Name**: `my-chat-db` (или любое имя)
   - **Database**: `chatdb` (или любое имя)
   - **User**: `chatuser` (или любое имя)
   - **Region**: Выберите тот же регион, где ваш сервер
   - **PostgreSQL Version**: 15 или 16 (рекомендуется)
   - **Plan**: Free (для начала)
4. Нажмите **"Create Database"**
5. Дождитесь создания (1-2 минуты)

## Шаг 2: Получите Connection String

1. После создания БД откройте её в панели Render
2. Найдите раздел **"Connections"**
3. Скопируйте **"Internal Database URL"** (для сервисов на Render)
   - Или **"External Database URL"** (если нужно подключаться извне)
4. Формат будет: `postgresql://user:password@host:5432/database`

## Шаг 3: Создайте таблицы в новой БД

Выполните этот SQL в SQL Editor Render PostgreSQL (или через psql):

```sql
-- Таблица пользователей
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Таблица чатов
CREATE TABLE IF NOT EXISTS chats (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    is_group BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Связь пользователей и чатов
CREATE TABLE IF NOT EXISTS chat_users (
    chat_id INTEGER REFERENCES chats(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (chat_id, user_id)
);

-- Таблица сообщений
CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    chat_id INTEGER REFERENCES chats(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Индексы для производительности
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_users_chat_id ON chat_users(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_users_user_id ON chat_users(user_id);
```

## Шаг 4: Обновите переменные окружения на сервере

1. Зайдите в ваш сервис на Render
2. Перейдите в **Environment**
3. Найдите переменную `DATABASE_URL` (или `POSTGRES_URL`)
4. Замените значение на новый connection string из шага 2
5. **Сохраните** изменения

## Шаг 5: Перезапустите сервер

1. В Render нажмите **"Manual Deploy"** → **"Clear build cache & deploy"**
2. Или просто перезапустите сервис

## Шаг 6: Проверьте работу

Попробуйте:
- Зарегистрировать нового пользователя
- Войти
- Создать чат

---

## Альтернатива: Neon PostgreSQL

Если хотите использовать Neon вместо Render PostgreSQL:

1. Зайдите на https://neon.tech
2. Создайте аккаунт (бесплатно)
3. Создайте новый проект
4. Получите connection string
5. Создайте таблицы (используйте SQL из шага 3)
6. Обновите `DATABASE_URL` на Render

Neon предоставляет бесплатный тариф с хорошими лимитами.

