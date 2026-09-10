/**
 * Баланс ученика, который видит преподаватель.
 *
 * Адресный депозит (target_teacher_id = преподаватель) закрывает только его занятия.
 * Неадресный пул (target_teacher_id IS NULL) закрывает остаток долгов всех преподавателей
 * пропорционально их непокрытому списанию — без дублирования одной оплаты каждому.
 *
 * Неиспользуемый остаток общего пула виден каждому привязанному преподавателю
 * (деньги ещё можно провести). После чужих списаний из пула остаток падает у всех.
 */

export const teacherVisibleBalance = ({
  myTargetedCredit,
  myLessonSpend,
  sharedCredit,
  unpaidTotal,
}) => {
  const targeted = Number(myTargetedCredit) || 0;
  const spent = Number(myLessonSpend) || 0;
  const shared = Number(sharedCredit) || 0;
  const unpaidAll = Number(unpaidTotal) || 0;
  const prepaid = Math.max(0, targeted - spent);
  const myUnpaid = Math.max(0, spent - targeted);
  const sharedRemaining = Math.max(0, shared - unpaidAll);
  const debtRemaining = Math.max(0, unpaidAll - shared);
  const myDebt = unpaidAll > 0 ? (myUnpaid * debtRemaining) / unpaidAll : 0;
  return prepaid - myDebt + sharedRemaining;
};

/**
 * @param {{ studentIdSql: string, teacherIdSql: string }} refs
 * @returns {string} SQL-выражение numeric баланса
 */
export const sqlTeacherVisibleStudentBalance = ({ studentIdSql, teacherIdSql }) => `
(
  WITH teacher_spend AS (
    SELECT created_by AS teacher_id,
           COALESCE(SUM(amount), 0)::numeric AS spent
    FROM transactions
    WHERE student_id = ${studentIdSql}
      AND type = 'lesson'
    GROUP BY created_by
  ),
  teacher_credit AS (
    SELECT target_teacher_id AS teacher_id,
           COALESCE(SUM(amount), 0)::numeric AS credit
    FROM transactions
    WHERE student_id = ${studentIdSql}
      AND type IN ('deposit', 'refund')
      AND target_teacher_id IS NOT NULL
    GROUP BY target_teacher_id
  ),
  shared AS (
    SELECT COALESCE(SUM(amount), 0)::numeric AS credit
    FROM transactions
    WHERE student_id = ${studentIdSql}
      AND type IN ('deposit', 'refund')
      AND target_teacher_id IS NULL
  ),
  wallets AS (
    SELECT COALESCE(sp.teacher_id, cr.teacher_id) AS teacher_id,
           COALESCE(cr.credit, 0) AS credit,
           COALESCE(sp.spent, 0) AS spent
    FROM teacher_spend sp
    FULL OUTER JOIN teacher_credit cr ON cr.teacher_id = sp.teacher_id
  ),
  wallets_marked AS (
    SELECT teacher_id,
           GREATEST(credit - spent, 0) AS prepaid,
           GREATEST(spent - credit, 0) AS unpaid
    FROM wallets
  ),
  totals AS (
    SELECT COALESCE(SUM(unpaid), 0) AS unpaid_total FROM wallets_marked
  )
  SELECT (
    COALESCE(wm.prepaid, 0)
    - CASE
        WHEN t.unpaid_total > 0
          THEN COALESCE(wm.unpaid, 0) * GREATEST(t.unpaid_total - sh.credit, 0) / t.unpaid_total
        ELSE 0
      END
    + GREATEST(sh.credit - t.unpaid_total, 0)
  )
  FROM shared sh
  CROSS JOIN totals t
  LEFT JOIN wallets_marked wm ON wm.teacher_id = ${teacherIdSql}
)
`;
