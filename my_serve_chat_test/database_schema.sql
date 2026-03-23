-- Схема базы данных для чат-приложения
-- Запустите этот скрипт в вашей PostgreSQL базе данных

-- Таблица пользователей
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    timezone VARCHAR(64) NOT NULL DEFAULT 'Europe/Moscow',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица чатов
CREATE TABLE IF NOT EXISTS chats (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_by INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица участников чатов (many-to-many)
CREATE TABLE IF NOT EXISTS chat_users (
    chat_id INTEGER REFERENCES chats(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (chat_id, user_id)
);

-- Таблица сообщений
CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    chat_id INTEGER REFERENCES chats(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для оптимизации запросов
CREATE INDEX IF NOT EXISTS idx_messages_chat_id_created_at ON messages (chat_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_chat_id_id ON messages (chat_id, id DESC);
CREATE INDEX IF NOT EXISTS idx_messages_user_id ON messages (user_id);
CREATE INDEX IF NOT EXISTS idx_chat_users_chat_id ON chat_users (chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_users_user_id ON chat_users (user_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_users_timezone ON users (timezone);

-- Комментарии к таблицам
COMMENT ON TABLE users IS 'Пользователи системы';
COMMENT ON TABLE chats IS 'Чаты между пользователями';
COMMENT ON TABLE chat_users IS 'Связь пользователей с чатами';
COMMENT ON TABLE messages IS 'Сообщения в чатах';

-- ============================================
-- Система учета занятий для репетиторского центра
-- ============================================

-- Таблица студентов (учеников)
CREATE TABLE IF NOT EXISTS students (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    parent_name VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255),
    notes TEXT,
    pay_by_bank_transfer BOOLEAN NOT NULL DEFAULT false,
    created_by INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица связи преподавателей и студентов (для общего реестра студентов)
-- Важно: видимость студентов для преподавателя определяется этой связью
CREATE TABLE IF NOT EXISTS teacher_students (
    id SERIAL PRIMARY KEY,
    teacher_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    student_id INTEGER REFERENCES students(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(teacher_id, student_id)
);

-- Таблица занятий
CREATE TABLE IF NOT EXISTS lessons (
    id SERIAL PRIMARY KEY,
    student_id INTEGER REFERENCES students(id) ON DELETE CASCADE,
    lesson_date DATE NOT NULL,
    lesson_time TIME,
    duration_minutes INTEGER DEFAULT 60,
    price DECIMAL(10, 2) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'attended' CHECK (status IN ('attended', 'missed', 'makeup', 'cancel_same_day')),
    is_chargeable BOOLEAN NOT NULL DEFAULT true,
    origin_lesson_id INTEGER REFERENCES lessons(id) ON DELETE SET NULL,
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
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_students_name_trgm
ON students USING gin (LOWER(REPLACE(TRIM(name), 'ё', 'е')) gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_lessons_student_id ON lessons(student_id);
CREATE INDEX IF NOT EXISTS idx_lessons_date ON lessons(lesson_date DESC);
CREATE INDEX IF NOT EXISTS idx_lessons_status ON lessons(status);
CREATE INDEX IF NOT EXISTS idx_lessons_origin_lesson_id ON lessons(origin_lesson_id);
CREATE INDEX IF NOT EXISTS idx_lessons_student_status_chargeable ON lessons(student_id, status, is_chargeable);
CREATE INDEX IF NOT EXISTS idx_transactions_student_id ON transactions(student_id);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at DESC);

-- Комментарии к новым таблицам
COMMENT ON TABLE students IS 'Ученики репетиторского центра';
COMMENT ON TABLE lessons IS 'Проведенные занятия';
COMMENT ON TABLE transactions IS 'Транзакции пополнения и списания баланса';

-- ============================================
-- Система отчетов для автоматического создания занятий
-- ============================================

-- Таблица отчетов
CREATE TABLE IF NOT EXISTS reports (
    id SERIAL PRIMARY KEY,
    report_date DATE NOT NULL,
    content TEXT NOT NULL,
    is_late BOOLEAN NOT NULL DEFAULT FALSE,
    created_by INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица связи отчетов и занятий (для возможности редактирования)
CREATE TABLE IF NOT EXISTS report_lessons (
    id SERIAL PRIMARY KEY,
    report_id INTEGER REFERENCES reports(id) ON DELETE CASCADE,
    lesson_id INTEGER REFERENCES lessons(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(report_id, lesson_id)
);

-- Индексы для отчетов
CREATE INDEX IF NOT EXISTS idx_reports_date ON reports(report_date DESC);
CREATE INDEX IF NOT EXISTS idx_reports_created_by ON reports(created_by);
CREATE INDEX IF NOT EXISTS idx_reports_is_late ON reports(is_late);
CREATE INDEX IF NOT EXISTS idx_report_lessons_report_id ON report_lessons(report_id);
CREATE INDEX IF NOT EXISTS idx_report_lessons_lesson_id ON report_lessons(lesson_id);

-- Бизнес-уникальность для защиты от дублей
CREATE UNIQUE INDEX IF NOT EXISTS ux_reports_created_by_report_date
ON reports(created_by, report_date);
CREATE UNIQUE INDEX IF NOT EXISTS ux_lessons_owner_student_date_null_time
ON lessons(created_by, student_id, lesson_date)
WHERE lesson_time IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_lessons_owner_student_date_time
ON lessons(created_by, student_id, lesson_date, lesson_time)
WHERE lesson_time IS NOT NULL;

-- Комментарии к таблицам отчетов
COMMENT ON TABLE reports IS 'Отчеты за день с автоматическим созданием занятий';
COMMENT ON TABLE report_lessons IS 'Связь отчетов и занятий для возможности редактирования';

-- ============================================
-- Reliability: idempotency и аудит
-- ============================================

CREATE TABLE IF NOT EXISTS idempotency_keys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    scope VARCHAR(120) NOT NULL,
    idempotency_key VARCHAR(200) NOT NULL,
    request_hash VARCHAR(128) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'completed')),
    response_status INTEGER,
    response_body JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    expires_at TIMESTAMP NOT NULL DEFAULT (CURRENT_TIMESTAMP + interval '24 hours'),
    UNIQUE(user_id, scope, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_expires_at ON idempotency_keys(expires_at);
CREATE INDEX IF NOT EXISTS idx_idempotency_scope_status ON idempotency_keys(scope, status);

CREATE TABLE IF NOT EXISTS audit_events (
    id BIGSERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    event_type VARCHAR(120) NOT NULL,
    entity_type VARCHAR(120),
    entity_id VARCHAR(120),
    payload JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_events_created_at ON audit_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_events_user_id ON audit_events(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_event_type ON audit_events(event_type);

