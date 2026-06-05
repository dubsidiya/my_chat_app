-- Рабочий баланс преподавателя: начисления с отчётов, выплаты, премии, корректировки

CREATE TABLE IF NOT EXISTS teacher_balance_transactions (
    id SERIAL PRIMARY KEY,
    teacher_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    type VARCHAR(30) NOT NULL CHECK (type IN ('lesson_income', 'salary', 'advance', 'premium', 'adjustment')),
    description TEXT,
    report_id INTEGER REFERENCES reports(id) ON DELETE SET NULL,
    lesson_id INTEGER REFERENCES lessons(id) ON DELETE SET NULL,
    created_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tbt_teacher_id ON teacher_balance_transactions(teacher_id);
CREATE INDEX IF NOT EXISTS idx_tbt_created_at ON teacher_balance_transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tbt_type ON teacher_balance_transactions(type);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tbt_lesson_income_report
    ON teacher_balance_transactions(report_id)
    WHERE type = 'lesson_income' AND report_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tbt_lesson_income_lesson
    ON teacher_balance_transactions(lesson_id)
    WHERE type = 'lesson_income' AND lesson_id IS NOT NULL;

COMMENT ON TABLE teacher_balance_transactions IS 'Рабочий баланс преподавателя: + с занятий/премий, − зарплата/аванс';
