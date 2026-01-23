-- Миграция: связь преподавателей со студентами (для общего реестра студентов)
-- Идея: students становится "общим справочником", а видимость определяется таблицей teacher_students.

CREATE TABLE IF NOT EXISTS teacher_students (
    id SERIAL PRIMARY KEY,
    teacher_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    student_id INTEGER REFERENCES students(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(teacher_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_teacher_students_teacher_id ON teacher_students(teacher_id);
CREATE INDEX IF NOT EXISTS idx_teacher_students_student_id ON teacher_students(student_id);

-- Backfill: каждому существующему студенту добавляем связь с его created_by (если есть)
INSERT INTO teacher_students (teacher_id, student_id)
SELECT s.created_by, s.id
FROM students s
WHERE s.created_by IS NOT NULL
ON CONFLICT DO NOTHING;

