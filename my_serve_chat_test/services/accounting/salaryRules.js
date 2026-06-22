/**
 * Единые правила расчёта зарплаты преподавателя (50% от занятий).
 *
 * Удержание для оплат на расчётный счёт:
 *  - наличные (students.pay_by_bank_transfer = false): база = полная цена занятия;
 *  - расчётный счёт (students.pay_by_bank_transfer = true): сначала с занятия
 *    удерживается комиссия+налоги, затем уже считается доля преподавателя.
 *
 * Пример: занятие 2400 ₽ по расчётному счёту → 2400 − 300 = 2100 → 50% = 1050 ₽.
 * Наличными то же занятие → 2400 → 50% = 1200 ₽.
 *
 * Держим константу и формулу в одном месте, чтобы все места расчёта зарплаты
 * (живые начисления на баланс, месячная зарплата, админ-выгрузка) совпадали.
 */

/** Удержание с одного занятия при оплате на расчётный счёт (комиссия + налоги). */
export const BANK_TRANSFER_LESSON_DEDUCTION = 300;

/** Доля преподавателя от базы занятия. */
export const SALARY_SHARE = 0.5;

/**
 * SQL-выражение «база занятия для расчёта зарплаты» (цена за вычетом удержания
 * по расчётному счёту, но не ниже нуля). Требует, чтобы к занятию был приджойнен
 * ученик (students) под алиасом studentAlias.
 */
export const sqlLessonSalaryBase = (lessonAlias = 'l', studentAlias = 's') =>
  `CASE WHEN COALESCE(${studentAlias}.pay_by_bank_transfer, false)
        THEN GREATEST(${lessonAlias}.price - ${BANK_TRANSFER_LESSON_DEDUCTION}, 0)
        ELSE ${lessonAlias}.price END`;

/** JS-аналог sqlLessonSalaryBase для расчётов в коде. */
export const lessonSalaryBase = (price, payByBankTransfer) => {
  const p = Number(price);
  const base = Number.isFinite(p) ? p : 0;
  if (!payByBankTransfer) return base;
  return Math.max(0, base - BANK_TRANSFER_LESSON_DEDUCTION);
};

/** Пояснение для UI/выгрузок. */
export const BANK_TRANSFER_DEDUCTION_NOTE =
  `По расчётному счёту - ${BANK_TRANSFER_LESSON_DEDUCTION} учтено`;
