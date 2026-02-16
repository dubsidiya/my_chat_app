-- Миграция: способ оплаты ученика — наличные или расчётный счёт
-- Для выписки по расчётному счёту (бухгалтерия) нужны только ученики с pay_by_bank_transfer = true

ALTER TABLE students
  ADD COLUMN IF NOT EXISTS pay_by_bank_transfer BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN students.pay_by_bank_transfer IS 'true = платит на расчётный счёт, false = наличными';
