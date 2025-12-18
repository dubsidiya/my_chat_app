-- Миграция: Добавление таблиц для системы отчетов
-- Запустите этот скрипт в вашей PostgreSQL базе данных

-- Таблица отчетов
CREATE TABLE IF NOT EXISTS reports (
    id SERIAL PRIMARY KEY,
    report_date DATE NOT NULL,
    content TEXT NOT NULL,
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
CREATE INDEX IF NOT EXISTS idx_report_lessons_report_id ON report_lessons(report_id);
CREATE INDEX IF NOT EXISTS idx_report_lessons_lesson_id ON report_lessons(lesson_id);

-- Комментарии к таблицам отчетов
COMMENT ON TABLE reports IS 'Отчеты за день с автоматическим созданием занятий';
COMMENT ON TABLE report_lessons IS 'Связь отчетов и занятий для возможности редактирования';

