/**
 * Smoke-check teacher balance:
 * 1) teacher can read own balance
 * 2) superuser can post salary/premium
 * 3) non-superuser cannot post admin transaction
 *
 * Run: node scripts/smoke-teacher-balance.js
 */
import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';
import {
  getMyTeacherBalance,
  getTeacherBalanceAdmin,
  postTeacherBalanceTransactionAdmin,
} from '../controllers/teacherBalanceController.js';
import { syncReportLessonIncome } from '../services/accounting/teacherBalanceService.js';

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

const run = async () => {
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

  if (!superuser) {
    console.warn('smoke-teacher-balance: SKIP admin checks (нет суперпользователя в SUPERUSER_*)');
  } else {
    const adminRes = makeRes();
    await getTeacherBalanceAdmin(
      { user: superuser, params: { teacherId: String(teacher.userId) }, query: {} },
      adminRes
    );
    assert(adminRes.statusCode === 200, `admin balance read failed: ${adminRes.statusCode}`);

    const premiumRes = makeRes();
    await postTeacherBalanceTransactionAdmin(
      {
        user: superuser,
        params: { teacherId: String(teacher.userId) },
        body: { type: 'premium', amount: 100, description: 'smoke premium' },
      },
      premiumRes
    );
    assert(premiumRes.statusCode === 201, `premium post failed: ${premiumRes.statusCode}`);

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
  }

  const reportRes = await pool.query(
    `SELECT id FROM reports WHERE created_by = $1 ORDER BY id DESC LIMIT 1`,
    [teacher.userId]
  );
  if (reportRes.rows.length > 0) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await syncReportLessonIncome(client, reportRes.rows[0].id, superuser?.userId ?? teacher.userId);
      await client.query('COMMIT');
    } finally {
      client.release();
    }
  }

  console.log('smoke-teacher-balance: OK');
};

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('smoke-teacher-balance: FAIL', e.message || e);
    process.exit(1);
  });
