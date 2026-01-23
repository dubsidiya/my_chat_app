-- Миграция: отметка "поздний отчет"
-- Поздний = отчет за дату, меньшую чем дата создания отчета

ALTER TABLE reports
ADD COLUMN IF NOT EXISTS is_late BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_reports_is_late ON reports(is_late);

-- Backfill для уже созданных отчетов
UPDATE reports
SET is_late = (report_date < created_at::date)
WHERE is_late = FALSE;

