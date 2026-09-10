-- Аудит M33: нет уникальности/индексов по нормализованному телефону и email ученика.
--
-- Поиск дубля в createStudent идёт по нормализованным выражениям, которые сейчас
-- не индексируются (seq scan на каждый create):
--   phone: regexp_replace(COALESCE(phone, ''), '\D', '', 'g') = $1
--   email: LOWER(TRIM(COALESCE(email, ''))) = $1
-- (см. studentsController.js:224-243)
--
-- ВАЖНО — почему НЕ UNIQUE:
-- В существующих данных уже могут быть дубли по нормализованному телефону/email
-- (ровно та гонка, что описана в M33). CREATE UNIQUE INDEX по такому выражению
-- прервётся с ошибкой 23505 на первой же паре дублей и откатит всю миграцию.
-- Поэтому здесь создаются ОБЫЧНЫЕ (не уникальные) функциональные индексы —
-- они ускоряют существующие regexp_replace/LOWER(TRIM(...)) lookups и безопасны
-- при любых данных.
--
-- Чтобы перейти к настоящей уникальности, нужен ОТДЕЛЬНЫЙ шаг дедупликации
-- (слить/переназначить дубли), и только ПОСЛЕ него —
--   CREATE UNIQUE INDEX IF NOT EXISTS uq_students_normalized_phone
--     ON students (regexp_replace(COALESCE(phone, ''), '\D', '', 'g'))
--     WHERE regexp_replace(COALESCE(phone, ''), '\D', '', 'g') <> '';
--   CREATE UNIQUE INDEX IF NOT EXISTS uq_students_normalized_email
--     ON students (LOWER(TRIM(COALESCE(email, ''))))
--     WHERE LOWER(TRIM(COALESCE(email, ''))) <> '';
-- Этот шаг здесь намеренно НЕ выполняется, чтобы не рисковать падением на данных.
--
-- Идемпотентно и безопасно к повторному запуску (CREATE INDEX IF NOT EXISTS).
-- Все используемые функции (regexp_replace, LOWER, TRIM, COALESCE) IMMUTABLE,
-- поэтому пригодны для функционального индекса.
-- Запуск: node scripts/run-migration.js migrations/add_students_normalized_contact_indexes.sql

CREATE INDEX IF NOT EXISTS idx_students_normalized_phone
ON students (regexp_replace(COALESCE(phone, ''), '\D', '', 'g'));

CREATE INDEX IF NOT EXISTS idx_students_normalized_email
ON students (LOWER(TRIM(COALESCE(email, ''))));
