-- Миграция: Добавление таблиц для системы учета занятий
-- Запустите этот скрипт в вашей PostgreSQL базе данных

-- Таблица студентов (учеников)
CREATE TABLE IF NOT EXISTS students (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    parent_name VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255),
    notes TEXT,
    created_by INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица занятий
CREATE TABLE IF NOT EXISTS lessons (
    id SERIAL PRIMARY KEY,
    student_id INTEGER REFERENCES students(id) ON DELETE CASCADE,
    lesson_date DATE NOT NULL,
    lesson_time TIME,
    duration_minutes INTEGER DEFAULT 60,
    price DECIMAL(10, 2) NOT NULL,
    notes TEXT,
    created_by INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица транзакций (пополнения и списания)
CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    student_id INTEGER REFERENCES students(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('deposit', 'lesson', 'refund')),
    description TEXT,
    lesson_id INTEGER REFERENCES lessons(id) ON DELETE SET NULL,
    created_by INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для оптимизации
CREATE INDEX IF NOT EXISTS idx_students_created_by ON students(created_by);
CREATE INDEX IF NOT EXISTS idx_lessons_student_id ON lessons(student_id);
CREATE INDEX IF NOT EXISTS idx_lessons_date ON lessons(lesson_date DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_student_id ON transactions(student_id);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at DESC);

-- Комментарии к новым таблицам
COMMENT ON TABLE students IS 'Ученики репетиторского центра';
COMMENT ON TABLE lessons IS 'Проведенные занятия';
COMMENT ON TABLE transactions IS 'Транзакции пополнения и списания баланса';

