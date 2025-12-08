-- Исправление таблицы messages: переименование sender_id в user_id
-- Выполните этот SQL в Neon SQL Editor

-- Проверяем, какая колонка существует
-- Если есть sender_id, переименовываем в user_id
DO $$
BEGIN
    -- Проверяем, существует ли колонка sender_id
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'messages' 
        AND column_name = 'sender_id'
    ) THEN
        -- Переименовываем sender_id в user_id
        ALTER TABLE messages RENAME COLUMN sender_id TO user_id;
        RAISE NOTICE 'Колонка sender_id переименована в user_id';
    ELSIF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'messages' 
        AND column_name = 'user_id'
    ) THEN
        -- Если нет ни sender_id, ни user_id, создаем user_id
        ALTER TABLE messages ADD COLUMN user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;
        
        -- Если есть sender_id, копируем данные
        IF EXISTS (
            SELECT 1 
            FROM information_schema.columns 
            WHERE table_name = 'messages' 
            AND column_name = 'sender_id'
        ) THEN
            UPDATE messages SET user_id = sender_id WHERE user_id IS NULL;
            ALTER TABLE messages DROP COLUMN sender_id;
        END IF;
        
        RAISE NOTICE 'Колонка user_id создана';
    ELSE
        RAISE NOTICE 'Колонка user_id уже существует';
    END IF;
END $$;

-- Проверяем результат
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'messages'
ORDER BY ordinal_position;

