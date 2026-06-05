import { sqlUserAccountingName } from '../../utils/userAccountingDisplaySql.js';

const PAYOUT_TYPES = new Set(['salary', 'advance']);

const toNumber = (v) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

const roundMoney = (v) => Math.round(toNumber(v));

/** Начало периода начислений на рабочий баланс (фиксировано). */
export const TEACHER_BALANCE_SYNC_FROM = '2026-06-01';

const isoDateOnly = (value) => {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  const s = String(value).slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(s) ? s : null;
};

export const isOnOrAfterTeacherBalanceSyncStart = (dateValue) => {
  const d = isoDateOnly(dateValue);
  return d != null && d >= TEACHER_BALANCE_SYNC_FROM;
};

export const teacherBalanceSyncToToday = () => new Date().toISOString().slice(0, 10);

export const computeReportIncomeAmount = async (db, reportId) => {
  const reportRes = await db.query(
    'SELECT id, created_by, report_date, is_late FROM reports WHERE id = $1',
    [reportId]
  );
  if (reportRes.rows.length === 0) return null;
  const report = reportRes.rows[0];
  if (!isOnOrAfterTeacherBalanceSyncStart(report.report_date)) {
    return {
      teacherId: report.created_by,
      amount: 0,
      reportDate: report.report_date,
      isLate: false,
      beforeSyncStart: true,
    };
  }
  if (report.is_late === true) {
    return { teacherId: report.created_by, amount: 0, reportDate: report.report_date, isLate: true };
  }
  const sumRes = await db.query(
    `SELECT COALESCE(SUM(l.price), 0) AS total
     FROM report_lessons rl
     JOIN lessons l ON l.id = rl.lesson_id
     WHERE rl.report_id = $1
       AND COALESCE(l.is_chargeable, true) = true`,
    [reportId]
  );
  const total = toNumber(sumRes.rows[0]?.total);
  return {
    teacherId: report.created_by,
    amount: roundMoney(total * 0.5),
    reportDate: report.report_date,
    isLate: false,
  };
};

export const computeLessonIncomeAmount = async (db, lessonId) => {
  const lessonRes = await db.query(
    `SELECT l.id, l.created_by, l.lesson_date, l.price, l.is_chargeable,
            EXISTS (SELECT 1 FROM report_lessons rl WHERE rl.lesson_id = l.id) AS in_report
     FROM lessons l
     WHERE l.id = $1`,
    [lessonId]
  );
  if (lessonRes.rows.length === 0) return null;
  const lesson = lessonRes.rows[0];
  if (!isOnOrAfterTeacherBalanceSyncStart(lesson.lesson_date)) {
    return { teacherId: lesson.created_by, amount: 0, lessonDate: lesson.lesson_date, beforeSyncStart: true };
  }
  if (lesson.in_report) return null;
  if (lesson.is_chargeable === false) {
    return { teacherId: lesson.created_by, amount: 0, lessonDate: lesson.lesson_date };
  }
  return {
    teacherId: lesson.created_by,
    amount: roundMoney(toNumber(lesson.price) * 0.5),
    lessonDate: lesson.lesson_date,
  };
};

export const deleteLessonIncomeForReport = async (client, reportId) => {
  await client.query(
    `DELETE FROM teacher_balance_transactions
     WHERE type = 'lesson_income' AND report_id = $1`,
    [reportId]
  );
};

export const deleteLessonIncomeForLessons = async (client, lessonIds) => {
  if (!Array.isArray(lessonIds) || lessonIds.length === 0) return;
  await client.query(
    `DELETE FROM teacher_balance_transactions
     WHERE type = 'lesson_income' AND lesson_id = ANY($1::int[])`,
    [lessonIds]
  );
};

export const deleteLessonIncomeForLesson = async (client, lessonId) => {
  await client.query(
    `DELETE FROM teacher_balance_transactions
     WHERE type = 'lesson_income' AND lesson_id = $1`,
    [lessonId]
  );
};

export const syncReportLessonIncome = async (client, reportId, actorUserId = null) => {
  const computed = await computeReportIncomeAmount(client, reportId);
  if (!computed) return;
  await deleteLessonIncomeForReport(client, reportId);
  if (computed.amount <= 0) return;
  const desc = computed.isLate
    ? null
    : `Начисление 50% с отчёта за ${computed.reportDate}`;
  await client.query(
    `INSERT INTO teacher_balance_transactions
       (teacher_id, amount, type, description, report_id, created_by)
     VALUES ($1, $2, 'lesson_income', $3, $4, $5)`,
    [computed.teacherId, computed.amount, desc, reportId, actorUserId]
  );
};

export const syncNoReportLessonIncome = async (client, lessonId, actorUserId = null) => {
  const computed = await computeLessonIncomeAmount(client, lessonId);
  if (!computed) return;
  await deleteLessonIncomeForLesson(client, lessonId);
  if (computed.amount <= 0) return;
  await client.query(
    `INSERT INTO teacher_balance_transactions
       (teacher_id, amount, type, description, lesson_id, created_by)
     VALUES ($1, $2, 'lesson_income', $3, $4, $5)`,
    [
      computed.teacherId,
      computed.amount,
      `Начисление 50% с занятия ${computed.lessonDate}`,
      lessonId,
      actorUserId,
    ]
  );
};

export const getTeacherBalance = async (db, teacherId) => {
  const res = await db.query(
    `SELECT COALESCE(SUM(amount), 0) AS balance
     FROM teacher_balance_transactions
     WHERE teacher_id = $1`,
    [teacherId]
  );
  return toNumber(res.rows[0]?.balance);
};

export const listTeacherBalanceTransactions = async (db, teacherId, { limit = 50, offset = 0 } = {}) => {
  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 200);
  const safeOffset = Math.max(Number(offset) || 0, 0);
  const res = await db.query(
    `SELECT t.id, t.teacher_id, t.amount, t.type, t.description,
            t.report_id, t.lesson_id, t.created_by, t.created_at,
            ${sqlUserAccountingName('u')} AS created_by_name
     FROM teacher_balance_transactions t
     LEFT JOIN users u ON u.id = t.created_by
     WHERE t.teacher_id = $1
     ORDER BY t.created_at DESC, t.id DESC
     LIMIT $2 OFFSET $3`,
    [teacherId, safeLimit, safeOffset]
  );
  return res.rows;
};

export const listTeachersWithBalances = async (db) => {
  const res = await db.query(
    `SELECT u.id,
            ${sqlUserAccountingName('u')} AS label,
            COALESCE(b.balance, 0) AS balance
     FROM users u
     LEFT JOIN (
       SELECT teacher_id, SUM(amount) AS balance
       FROM teacher_balance_transactions
       GROUP BY teacher_id
     ) b ON b.teacher_id = u.id
     WHERE EXISTS (
       SELECT 1 FROM teacher_balance_transactions t WHERE t.teacher_id = u.id
     )
     OR EXISTS (
       SELECT 1 FROM lessons l WHERE l.created_by = u.id
     )
     OR EXISTS (
       SELECT 1 FROM reports r WHERE r.created_by = u.id
     )
     ORDER BY label ASC`
  );
  return res.rows.map((r) => ({
    teacherId: r.id,
    label: r.label || '',
    balance: toNumber(r.balance),
  }));
};

const normalizePayoutAmount = (type, rawAmount) => {
  const n = toNumber(rawAmount);
  if (!Number.isFinite(n) || n === 0) return null;
  if (PAYOUT_TYPES.has(type)) return -Math.abs(roundMoney(n));
  if (type === 'premium') return Math.abs(roundMoney(n));
  if (type === 'adjustment') return roundMoney(n);
  return null;
};

export const createTeacherBalanceTransaction = async (client, {
  teacherId,
  type,
  amount,
  description,
  createdBy,
}) => {
  const allowed = new Set(['salary', 'advance', 'premium', 'adjustment']);
  if (!allowed.has(type)) {
    return { error: 'Некорректный тип операции' };
  }
  const normalized = normalizePayoutAmount(type, amount);
  if (normalized == null || normalized === 0) {
    return { error: 'Укажите ненулевую сумму' };
  }
  const desc = typeof description === 'string' ? description.trim() : '';
  if (!desc) {
    return { error: 'Укажите описание операции' };
  }
  const userCheck = await client.query('SELECT id FROM users WHERE id = $1', [teacherId]);
  if (userCheck.rows.length === 0) {
    return { error: 'Преподаватель не найден' };
  }
  const result = await client.query(
    `INSERT INTO teacher_balance_transactions
       (teacher_id, amount, type, description, created_by)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING *`,
    [teacherId, normalized, type, desc, createdBy]
  );
  return { row: result.rows[0] };
};

/** Удалить начисления до даты старта или по удалённым отчётам/занятиям. */
export const purgeLessonIncomeBeforeSyncStart = async (client) => {
  await client.query(
    `DELETE FROM teacher_balance_transactions t
     WHERE t.type = 'lesson_income'
       AND (
         (t.report_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM reports r
           WHERE r.id = t.report_id AND r.report_date < $1::date
         ))
         OR (t.lesson_id IS NOT NULL AND EXISTS (
           SELECT 1 FROM lessons l
           WHERE l.id = t.lesson_id AND l.lesson_date < $1::date
         ))
         OR (t.report_id IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM reports r WHERE r.id = t.report_id
         ))
         OR (t.lesson_id IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM lessons l WHERE l.id = t.lesson_id
         ))
       )`,
    [TEACHER_BALANCE_SYNC_FROM]
  );
};

/** Массовая синхронизация начислений с отчётов и занятий без отчёта за период. */
export const syncTeacherBalancesForPeriod = async (client, { from, to, actorUserId = null }) => {
  await purgeLessonIncomeBeforeSyncStart(client);

  const reportsRes = await client.query(
    `SELECT id FROM reports
     WHERE report_date >= $1::date AND report_date <= $2::date
     ORDER BY id ASC`,
    [from, to]
  );
  for (const r of reportsRes.rows) {
    await syncReportLessonIncome(client, r.id, actorUserId);
  }
  const lessonsRes = await client.query(
    `SELECT l.id
     FROM lessons l
     WHERE l.lesson_date >= $1::date AND l.lesson_date <= $2::date
       AND COALESCE(l.is_chargeable, true) = true
       AND NOT EXISTS (SELECT 1 FROM report_lessons rl WHERE rl.lesson_id = l.id)
     ORDER BY l.id ASC`,
    [from, to]
  );
  for (const l of lessonsRes.rows) {
    await syncNoReportLessonIncome(client, l.id, actorUserId);
  }
  return {
    reportsSynced: reportsRes.rows.length,
    lessonsSynced: lessonsRes.rows.length,
  };
};

export const TEACHER_BALANCE_TYPE_LABELS = {
  lesson_income: 'Начисление с занятий',
  salary: 'Зарплата',
  advance: 'Аванс',
  premium: 'Премия',
  adjustment: 'Корректировка',
};
