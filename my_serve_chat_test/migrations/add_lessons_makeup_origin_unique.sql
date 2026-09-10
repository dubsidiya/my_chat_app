-- Один пропуск/отмена может быть закрыт только одной отработкой.
-- Исторические дубли не удаляем и не сторнируем: у лишних makeup снимаем origin,
-- чтобы уникальный индекс мог создаться, а старые списания остались как есть.
--
-- Запуск: node scripts/run-migration.js migrations/add_lessons_makeup_origin_unique.sql

WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (PARTITION BY origin_lesson_id ORDER BY id ASC) AS rn
  FROM lessons
  WHERE status = 'makeup'
    AND origin_lesson_id IS NOT NULL
)
UPDATE lessons l
SET origin_lesson_id = NULL
FROM ranked r
WHERE l.id = r.id
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_lessons_makeup_origin
ON lessons (origin_lesson_id)
WHERE status = 'makeup' AND origin_lesson_id IS NOT NULL;
