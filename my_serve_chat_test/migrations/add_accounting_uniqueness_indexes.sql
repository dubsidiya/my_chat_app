-- Миграция: очистка дублей + защита от дублей в учете занятий и отчетах.
-- Идемпотентна. Совместима с uq_report_lessons_lesson_id:
-- связи переносим UPDATE/DELETE, а не INSERT ... ON CONFLICT (report_id, lesson_id)
-- (этот арбитр не ловит уникальность по одному lesson_id → 23505 и откат всего файла).

-- 1) Дубли отчётов (created_by, report_date).
--    Оставляем отчёт с большим числом занятий, при равенстве — с более длинным
--    текстом, затем меньший id. Связи с дублей переезжают на него.
CREATE TEMP TABLE tmp_report_id_map ON COMMIT DROP AS
SELECT r.id AS old_id, k.keep_id
FROM reports r
JOIN (
  SELECT created_by, report_date,
         (ARRAY_AGG(id ORDER BY lesson_cnt DESC, content_len DESC, id ASC))[1] AS keep_id
  FROM (
    SELECT r2.id,
           r2.created_by,
           r2.report_date,
           (SELECT COUNT(*) FROM report_lessons rl WHERE rl.report_id = r2.id) AS lesson_cnt,
           length(COALESCE(r2.content, '')) AS content_len
    FROM reports r2
  ) scored
  GROUP BY created_by, report_date
  HAVING COUNT(*) > 1
) k ON r.created_by = k.created_by AND r.report_date = k.report_date
WHERE r.id <> k.keep_id;

DELETE FROM report_lessons rl
USING tmp_report_id_map m
WHERE rl.report_id = m.old_id
  AND EXISTS (
    SELECT 1 FROM report_lessons x
    WHERE x.report_id = m.keep_id AND x.lesson_id = rl.lesson_id
  );

DELETE FROM report_lessons
WHERE id IN (
  SELECT id FROM (
    SELECT rl.id,
           ROW_NUMBER() OVER (PARTITION BY m.keep_id, rl.lesson_id ORDER BY rl.id) AS rn
    FROM report_lessons rl
    JOIN tmp_report_id_map m ON rl.report_id = m.old_id
  ) ranked
  WHERE ranked.rn > 1
);

UPDATE report_lessons rl
SET report_id = m.keep_id
FROM tmp_report_id_map m
WHERE rl.report_id = m.old_id;

DELETE FROM reports r
USING tmp_report_id_map m
WHERE r.id = m.old_id;

-- 2) Дубли уроков (created_by, student_id, lesson_date, lesson_time):
--    оставляем минимальный id, переносим ссылки, затем удаляем дубли.
CREATE TEMP TABLE tmp_lesson_id_map ON COMMIT DROP AS
SELECT l.id AS old_id, d.keep_id
FROM lessons l
JOIN (
  SELECT created_by, student_id, lesson_date, lesson_time, MIN(id) AS keep_id
  FROM lessons
  GROUP BY created_by, student_id, lesson_date, lesson_time
  HAVING COUNT(*) > 1
) d
  ON l.created_by = d.created_by
 AND l.student_id = d.student_id
 AND l.lesson_date = d.lesson_date
 AND l.lesson_time IS NOT DISTINCT FROM d.lesson_time
WHERE l.id <> d.keep_id;

UPDATE transactions t
SET lesson_id = m.keep_id
FROM tmp_lesson_id_map m
WHERE t.lesson_id = m.old_id;

-- H14: на одно занятие — одно списание. После переноса lesson_id на keep
-- второе type='lesson' не оставляем (баланс иначе расходится с экспортом).
DELETE FROM transactions
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY lesson_id ORDER BY id) AS rn
    FROM transactions
    WHERE type = 'lesson' AND lesson_id IS NOT NULL
  ) ranked
  WHERE ranked.rn > 1
);

UPDATE report_lessons rl
SET lesson_id = chosen.keep_id
FROM (
  SELECT rl2.id, m.keep_id,
         ROW_NUMBER() OVER (PARTITION BY m.keep_id ORDER BY rl2.id) AS rn
  FROM report_lessons rl2
  JOIN tmp_lesson_id_map m ON rl2.lesson_id = m.old_id
  WHERE NOT EXISTS (
    SELECT 1 FROM report_lessons x WHERE x.lesson_id = m.keep_id
  )
    AND NOT EXISTS (
      SELECT 1 FROM report_lessons x
      WHERE x.report_id = rl2.report_id AND x.lesson_id = m.keep_id
    )
) chosen
WHERE rl.id = chosen.id
  AND chosen.rn = 1;

DELETE FROM lessons l
USING tmp_lesson_id_map m
WHERE l.id = m.old_id;

-- 3) Уникальные индексы (после очистки дублей)
CREATE UNIQUE INDEX IF NOT EXISTS ux_reports_created_by_report_date
ON reports (created_by, report_date);

CREATE UNIQUE INDEX IF NOT EXISTS ux_lessons_owner_student_date_null_time
ON lessons (created_by, student_id, lesson_date)
WHERE lesson_time IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_lessons_owner_student_date_time
ON lessons (created_by, student_id, lesson_date, lesson_time)
WHERE lesson_time IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_report_lessons_lesson_id
ON report_lessons (lesson_id)
WHERE lesson_id IS NOT NULL;
