-- Аудит M31: нет составного индекса lessons(created_by, lesson_date).
-- Range-скан по преподавателю и дате (/reports/salary, findMonthlyNoReportAmount,
-- computeTeacherWorkProfile, heatmap) идёт seq scan'ом: единственные индексы с
-- created_by впереди — частичные уникальные, для range-скана не годятся.
--
-- Идемпотентно и безопасно к повторному запуску (CREATE INDEX IF NOT EXISTS).
-- Запуск: node scripts/run-migration.js migrations/add_lessons_created_by_date_index.sql
-- (или автоматически через scripts/apply-critical-migrations.js)

CREATE INDEX IF NOT EXISTS idx_lessons_created_by_date
ON lessons (created_by, lesson_date);
