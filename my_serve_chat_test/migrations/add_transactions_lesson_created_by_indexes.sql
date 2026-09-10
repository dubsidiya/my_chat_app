-- Аудит M32: нет индексов transactions(lesson_id) и transactions(created_by).
-- Каждый deleteLesson сканирует transactions целиком, удерживая блокировки
-- внутри открытой транзакции; агрегации по преподавателю тоже идут seq scan'ом.
--
-- Идемпотентно и безопасно к повторному запуску (CREATE INDEX IF NOT EXISTS).
-- Запуск: node scripts/run-migration.js migrations/add_transactions_lesson_created_by_indexes.sql
-- (или автоматически через scripts/apply-critical-migrations.js)

CREATE INDEX IF NOT EXISTS idx_transactions_lesson_id
ON transactions (lesson_id);

CREATE INDEX IF NOT EXISTS idx_transactions_created_by
ON transactions (created_by);
