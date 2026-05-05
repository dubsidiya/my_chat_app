ALTER TABLE transactions
ADD COLUMN IF NOT EXISTS target_teacher_id INTEGER REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_transactions_target_teacher_id
ON transactions(target_teacher_id);
