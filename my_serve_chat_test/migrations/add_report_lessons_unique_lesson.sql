-- Гарантируем, что одно занятие может быть связано максимум с одним отчётом.
-- Если исторически появились дубли, оставляем запись с минимальным id.
WITH duplicate_links AS (
  SELECT lesson_id, MIN(id) AS keep_id
  FROM report_lessons
  WHERE lesson_id IS NOT NULL
  GROUP BY lesson_id
  HAVING COUNT(*) > 1
)
DELETE FROM report_lessons rl
USING duplicate_links d
WHERE rl.lesson_id = d.lesson_id
  AND rl.id <> d.keep_id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_report_lessons_lesson_id
  ON report_lessons (lesson_id)
  WHERE lesson_id IS NOT NULL;
