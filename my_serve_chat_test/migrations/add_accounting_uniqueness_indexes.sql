-- Миграция: очистка дублей + защита от дублей в учете занятий и отчетах.
-- Скрипт идемпотентный: повторный запуск безопасен.

-- 1) Дедуп отчетов (created_by, report_date):
--    оставляем минимальный id, переносим связи report_lessons в "основной" отчет, затем удаляем дубли.
INSERT INTO report_lessons (report_id, lesson_id)
WITH report_id_map AS (
  SELECT r.id AS old_id, d.keep_id
  FROM reports r
  JOIN (
    SELECT created_by, report_date, MIN(id) AS keep_id, COUNT(*) AS cnt
    FROM reports
    GROUP BY created_by, report_date
    HAVING COUNT(*) > 1
  ) d
    ON r.created_by = d.created_by
   AND r.report_date = d.report_date
  WHERE r.id <> d.keep_id
)
SELECT m.keep_id, rl.lesson_id
FROM report_id_map m
JOIN report_lessons rl ON rl.report_id = m.old_id
ON CONFLICT (report_id, lesson_id) DO NOTHING;

DELETE FROM reports
WHERE id IN (
  SELECT r.id
  FROM reports r
  JOIN (
    SELECT created_by, report_date, MIN(id) AS keep_id, COUNT(*) AS cnt
    FROM reports
    GROUP BY created_by, report_date
    HAVING COUNT(*) > 1
  ) d
    ON r.created_by = d.created_by
   AND r.report_date = d.report_date
  WHERE r.id <> d.keep_id
);

-- 2) Дедуп уроков (created_by, student_id, lesson_date, lesson_time):
--    оставляем минимальный id, переносим ссылки в transactions/report_lessons, затем удаляем дубли.
UPDATE transactions t
SET lesson_id = m.keep_id
FROM (
  SELECT l.id AS old_id, d.keep_id
  FROM lessons l
  JOIN (
    SELECT created_by, student_id, lesson_date, lesson_time, MIN(id) AS keep_id, COUNT(*) AS cnt
    FROM lessons
    GROUP BY created_by, student_id, lesson_date, lesson_time
    HAVING COUNT(*) > 1
  ) d
    ON l.created_by = d.created_by
   AND l.student_id = d.student_id
   AND l.lesson_date = d.lesson_date
   AND l.lesson_time IS NOT DISTINCT FROM d.lesson_time
  WHERE l.id <> d.keep_id
) m
WHERE t.lesson_id = m.old_id;

INSERT INTO report_lessons (report_id, lesson_id)
SELECT rl.report_id, m.keep_id
FROM report_lessons rl
JOIN (
  SELECT l.id AS old_id, d.keep_id
  FROM lessons l
  JOIN (
    SELECT created_by, student_id, lesson_date, lesson_time, MIN(id) AS keep_id, COUNT(*) AS cnt
    FROM lessons
    GROUP BY created_by, student_id, lesson_date, lesson_time
    HAVING COUNT(*) > 1
  ) d
    ON l.created_by = d.created_by
   AND l.student_id = d.student_id
   AND l.lesson_date = d.lesson_date
   AND l.lesson_time IS NOT DISTINCT FROM d.lesson_time
  WHERE l.id <> d.keep_id
) m ON rl.lesson_id = m.old_id
ON CONFLICT (report_id, lesson_id) DO NOTHING;

DELETE FROM lessons
WHERE id IN (
  SELECT l.id
  FROM lessons l
  JOIN (
    SELECT created_by, student_id, lesson_date, lesson_time, MIN(id) AS keep_id, COUNT(*) AS cnt
    FROM lessons
    GROUP BY created_by, student_id, lesson_date, lesson_time
    HAVING COUNT(*) > 1
  ) d
    ON l.created_by = d.created_by
   AND l.student_id = d.student_id
   AND l.lesson_date = d.lesson_date
   AND l.lesson_time IS NOT DISTINCT FROM d.lesson_time
  WHERE l.id <> d.keep_id
);

-- 3) Уникальные индексы (после очистки дублей)
CREATE UNIQUE INDEX IF NOT EXISTS ux_reports_created_by_report_date
ON reports (created_by, report_date);

CREATE UNIQUE INDEX IF NOT EXISTS ux_lessons_owner_student_date_null_time
ON lessons (created_by, student_id, lesson_date)
WHERE lesson_time IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_lessons_owner_student_date_time
ON lessons (created_by, student_id, lesson_date, lesson_time)
WHERE lesson_time IS NOT NULL;
