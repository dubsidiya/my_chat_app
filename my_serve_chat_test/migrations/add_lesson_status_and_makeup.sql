-- Статусы уроков + флаг списания для правил пропусков/отработок/отмены в день.
ALTER TABLE lessons
  ADD COLUMN IF NOT EXISTS status VARCHAR(32) NOT NULL DEFAULT 'attended',
  ADD COLUMN IF NOT EXISTS is_chargeable BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS origin_lesson_id INTEGER REFERENCES lessons(id) ON DELETE SET NULL;

ALTER TABLE lessons
  DROP CONSTRAINT IF EXISTS chk_lessons_status;

ALTER TABLE lessons
  ADD CONSTRAINT chk_lessons_status
  CHECK (status IN ('attended', 'missed', 'makeup', 'cancel_same_day'));

CREATE INDEX IF NOT EXISTS idx_lessons_status ON lessons(status);
CREATE INDEX IF NOT EXISTS idx_lessons_origin_lesson_id ON lessons(origin_lesson_id);
CREATE INDEX IF NOT EXISTS idx_lessons_student_status_chargeable
ON lessons(student_id, status, is_chargeable);
