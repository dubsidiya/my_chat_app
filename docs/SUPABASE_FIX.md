# Исправление ошибки подключения к Supabase

## Проблема
Ошибка: `connect ENETUNREACH` с IPv6 адресом - сервер на Render не может подключиться к Supabase через IPv6.

## Решение

### 1. Получите правильный Connection String в Supabase

1. Зайдите на https://app.supabase.com
2. Выберите ваш проект
3. Перейдите в **Settings** → **Database**
4. Найдите раздел **Connection string**
5. Используйте один из вариантов:

#### Вариант А: Connection Pooling (рекомендуется)
- Выберите **"Transaction mode"** или **"Session mode"**
- Скопируйте строку вида:
  ```
  postgresql://postgres.xxxxx:[YOUR-PASSWORD]@aws-0-[region].pooler.supabase.com:6543/postgres
  ```
- Порт **6543** - это pooling, обычно работает через IPv4

#### Вариант Б: Прямое подключение
- Используйте строку с портом **5432**
- Убедитесь, что хост содержит IPv4 адрес (например, `aws-0-[region].pooler.supabase.com`)

### 2. Обновите переменную окружения на Render

1. Зайдите на https://dashboard.render.com
2. Выберите ваш сервис `my-server-chat`
3. Перейдите в раздел **Environment**
4. Найдите переменную:
   - `DATABASE_URL` или
   - `POSTGRES_URL` или
   - `SUPABASE_DB_URL`
5. Замените значение на новый connection string из Supabase
6. **Сохраните изменения**

### 3. Перезапустите сервер

1. В Render нажмите **"Manual Deploy"** → **"Clear build cache & deploy"**
2. Или просто перезапустите сервис

### 4. Проверьте результат

Попробуйте войти в приложение снова. Ошибка `ENETUNREACH` должна исчезнуть.

---

## Если проблема сохраняется

1. Проверьте логи на Render - должны исчезнуть ошибки подключения
2. Убедитесь, что используете правильный пароль из Supabase
3. Проверьте, что таблицы созданы в Supabase (см. инструкцию по созданию таблиц)

