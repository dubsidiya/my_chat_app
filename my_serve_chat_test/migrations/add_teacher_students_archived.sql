-- Архив / выпускники: персонально на связи преподаватель ↔ ученик.
-- Ученик и история (занятия, транзакции, отчёты) остаются; из активного списка и дневного отчёта убирается.

ALTER TABLE teacher_students
  ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE teacher_students
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ NULL;

CREATE INDEX IF NOT EXISTS idx_teacher_students_teacher_archived
  ON teacher_students (teacher_id, is_archived);

COMMENT ON COLUMN teacher_students.is_archived IS
  'Выпускник для этого преподавателя: скрыт из активного списка и дневного отчёта, данные сохранены';
COMMENT ON COLUMN teacher_students.archived_at IS
  'Когда преподаватель отправил ученика в выпускники';
