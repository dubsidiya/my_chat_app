/**
 * Smoke-check teacher balance accrual logic.
 *
 * Run: node scripts/smoke-teacher-balance.js
 */
import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';
import {
  computeReportIncomeAmount,
  computeLessonIncomeAmount,
  getTeacherBalance,
  syncReportLessonIncome,
  syncNoReportLessonIncome,
  syncTeacherBalancesForPeriod,
  TEACHER_BALANCE_SYNC_FROM,
  isOnOrAfterTeacherBalanceSyncStart,
} from '../services/accounting/teacherBalanceService.js';
import {
  getMyTeacherBalance,
  postTeacherBalanceTransactionAdmin,
} from '../controllers/teacherBalanceController.js';

const makeRes = () => ({
  statusCode: 200,
  body: null,
  status(code) {
    this.statusCode = code;
    return this;
  },
  json(payload) {
    this.body = payload;
    return this;
  },
});

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

const assertEq = (actual, expected, msg) => {
  if (actual !== expected) {
    throw new Error(`${msg}: expected ${expected}, got ${actual}`);
  }
};

const run = async () => {
  assert(isOnOrAfterTeacherBalanceSyncStart('2026-06-01'), 'sync start boundary');
  assert(!isOnOrAfterTeacherBalanceSyncStart('2026-05-31'), 'pre-sync date excluded');

  const usersRes = await pool.query('SELECT id, email FROM users ORDER BY id ASC');
  assert(usersRes.rowCount > 0, 'Нет пользователей');

  const users = usersRes.rows.map((u) => ({
    userId: Number(u.id),
    email: String(u.email || ''),
    username: String(u.email || ''),
  }));

  const superuser = users.find((u) => isSuperuser(u)) || null;
  const teacher = users.find((u) => !isSuperuser(u)) || users[0];
  assert(teacher, 'Нет преподавателя для smoke-теста');

  const myRes = makeRes();
  await getMyTeacherBalance({ user: teacher }, myRes);
  assert(myRes.statusCode === 200, `teacher balance read failed: ${myRes.statusCode}`);
  assert(typeof myRes.body?.balance === 'number', 'balance missing');

  if (superuser) {
    const forbiddenRes = makeRes();
    await postTeacherBalanceTransactionAdmin(
      {
        user: teacher,
        params: { teacherId: String(teacher.userId) },
        body: { type: 'salary', amount: 50, description: 'smoke forbidden' },
      },
      forbiddenRes
    );
    assert(forbiddenRes.statusCode === 403, `non-superuser must get 403, got ${forbiddenRes.statusCode}`);
  } else {
    console.warn('smoke-teacher-balance: SKIP admin payout check (нет суперпользователя)');
  }

  const inPeriodReport = await pool.query(
    `SELECT r.id, r.created_by, r.is_late,
            COALESCE(SUM(CASE WHEN COALESCE(l.is_chargeable, true) THEN l.price ELSE 0 END), 0) AS total
     FROM reports r
     LEFT JOIN report_lessons rl ON rl.report_id = r.id
     LEFT JOIN lessons l ON l.id = rl.lesson_id
     WHERE r.report_date >= $1::date
       AND r.is_late = false
     GROUP BY r.id
     HAVING COALESCE(SUM(CASE WHEN COALESCE(l.is_chargeable, true) THEN l.price ELSE 0 END), 0) > 0
     ORDER BY r.id DESC
     LIMIT 1`,
    [TEACHER_BALANCE_SYNC_FROM]
  );

  if (inPeriodReport.rows.length > 0) {
    const row = inPeriodReport.rows[0];
    const computed = await computeReportIncomeAmount(pool, row.id);
    const expected = Math.round(Number(row.total) * 0.5);
    assertEq(computed?.amount, expected, 'report income 50%');
  } else {
    console.warn('smoke-teacher-balance: SKIP report 50% check (нет подходящего отчёта)');
  }

  const lateReport = await pool.query(
    `SELECT id FROM reports
     WHERE report_date >= $1::date AND is_late = true
     ORDER BY id DESC LIMIT 1`,
    [TEACHER_BALANCE_SYNC_FROM]
  );
  if (lateReport.rows.length > 0) {
    const computed = await computeReportIncomeAmount(pool, lateReport.rows[0].id);
    assertEq(computed?.amount, 0, 'late report income');
  }

  const preSyncReport = await pool.query(
    `SELECT id FROM reports
     WHERE report_date < $1::date
     ORDER BY id DESC LIMIT 1`,
    [TEACHER_BALANCE_SYNC_FROM]
  );
  if (preSyncReport.rows.length > 0) {
    const computed = await computeReportIncomeAmount(pool, preSyncReport.rows[0].id);
    assertEq(computed?.amount, 0, 'pre-sync report income');
  }

  const noReportLesson = await pool.query(
    `SELECT l.id
     FROM lessons l
     WHERE l.lesson_date >= $1::date
       AND COALESCE(l.is_chargeable, true) = true
       AND NOT EXISTS (SELECT 1 FROM report_lessons rl WHERE rl.lesson_id = l.id)
     ORDER BY l.id DESC
     LIMIT 1`,
    [TEACHER_BALANCE_SYNC_FROM]
  );
  if (noReportLesson.rows.length > 0) {
    const lessonId = noReportLesson.rows[0].id;
    const lessonRow = await pool.query(
      'SELECT price FROM lessons WHERE id = $1',
      [lessonId]
    );
    const computed = await computeLessonIncomeAmount(pool, lessonId);
    const expected = Math.round(Number(lessonRow.rows[0].price) * 0.5);
    assertEq(computed?.amount, expected, 'no-report lesson income 50%');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    if (inPeriodReport.rows.length > 0) {
      const reportId = inPeriodReport.rows[0].id;
      const teacherId = inPeriodReport.rows[0].created_by;
      const balanceBefore = await getTeacherBalance(client, teacherId);
      await syncReportLessonIncome(client, reportId, teacher.userId);

      const incomeRow = await client.query(
        `SELECT amount FROM teacher_balance_transactions
         WHERE type = 'lesson_income' AND report_id = $1`,
        [reportId]
      );
      assert(incomeRow.rowCount === 1, 'single lesson_income per report');

      await syncReportLessonIncome(client, reportId, teacher.userId);
      const incomeRow2 = await client.query(
        `SELECT COUNT(*)::int AS c FROM teacher_balance_transactions
         WHERE type = 'lesson_income' AND report_id = $1`,
        [reportId]
      );
      assertEq(incomeRow2.rows[0].c, 1, 'idempotent report sync');

      const balanceAfter = await getTeacherBalance(client, teacherId);
      assert(
        balanceAfter >= balanceBefore,
        'balance must not drop after idempotent report sync'
      );
    }

    if (superuser && inPeriodReport.rows.length > 0) {
      const teacherId = inPeriodReport.rows[0].created_by;
      const balanceBeforePayout = await getTeacherBalance(client, teacherId);
      const payout = await client.query(
        `INSERT INTO teacher_balance_transactions
           (teacher_id, amount, type, description, created_by)
         VALUES ($1, -100, 'salary', 'smoke payout', $2)
         RETURNING id`,
        [teacherId, superuser.userId]
      );
      assert(payout.rowCount === 1, 'payout insert');

      await syncTeacherBalancesForPeriod(client, {
        from: TEACHER_BALANCE_SYNC_FROM,
        to: '2099-12-31',
        actorUserId: superuser.userId,
      });

      const payoutStill = await client.query(
        'SELECT id FROM teacher_balance_transactions WHERE id = $1',
        [payout.rows[0].id]
      );
      assert(payoutStill.rowCount === 1, 'sync must not delete salary payouts');

      const balanceAfterPayout = await getTeacherBalance(client, teacherId);
      assert(
        balanceAfterPayout <= balanceBeforePayout - 100,
        'payout must reduce balance'
      );
    }

    await client.query('ROLLBACK');
  } finally {
    client.release();
  }

  console.log('smoke-teacher-balance: OK');
};

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('smoke-teacher-balance: FAIL', e.message || e);
    process.exit(1);
  });
