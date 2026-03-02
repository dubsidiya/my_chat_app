/**
 * Smoke-check reliability improvements:
 * - idempotency replay for createLesson/createReport/applyPayments
 * - no duplicate side effects on repeated request with same key
 *
 * Run:
 *   node scripts/smoke-accounting-reliability.js
 */
import pool from '../db.js';
import { createLesson, deleteLesson } from '../controllers/lessonsController.js';
import { createReport, deleteReport } from '../controllers/reportsController.js';
import { applyPayments } from '../controllers/bankStatementController.js';
import { getDateInTimeZoneISO, getUserTimeZone } from '../utils/timezone.js';

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
  send(payload) {
    this.body = payload;
    return this;
  },
});

const addDays = (isoDate, delta) => {
  const d = new Date(`${isoDate}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
};

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

const run = async () => {
  const seed = await pool.query(
    `SELECT ts.teacher_id, ts.student_id
     FROM teacher_students ts
     ORDER BY ts.created_at DESC
     LIMIT 1`
  );
  assert(seed.rowCount > 0, 'Нет данных teacher_students для smoke-теста');
  const teacherId = seed.rows[0].teacher_id;
  const studentId = seed.rows[0].student_id;

  // -------- createLesson idempotency --------
  const now = new Date();
  const lessonDate = now.toISOString().slice(0, 10);
  const hh = String((now.getUTCHours() + 2) % 24).padStart(2, '0');
  const mm = String((now.getUTCMinutes() + 7) % 60).padStart(2, '0');
  const lessonTime = `${hh}:${mm}`;
  const lessonKey = `smoke-lesson-${Date.now()}`;

  const lessonReq1 = {
    user: { userId: teacherId },
    params: { studentId: String(studentId) },
    body: {
      lesson_date: lessonDate,
      lesson_time: lessonTime,
      duration_minutes: 60,
      price: 1234,
      notes: 'smoke',
    },
    headers: { 'idempotency-key': lessonKey },
  };
  const lessonReq2 = {
    ...lessonReq1,
    body: { ...lessonReq1.body },
    headers: { ...lessonReq1.headers },
  };

  const lessonRes1 = makeRes();
  await createLesson(lessonReq1, lessonRes1);
  assert(lessonRes1.statusCode === 201, `createLesson #1 статус ${lessonRes1.statusCode}`);
  assert(lessonRes1.body?.id, 'createLesson #1 не вернул id');
  const lessonRes2 = makeRes();
  await createLesson(lessonReq2, lessonRes2);
  assert(lessonRes2.statusCode === 201, `createLesson #2 статус ${lessonRes2.statusCode}`);
  assert(
    Number(lessonRes2.body?.id) === Number(lessonRes1.body?.id),
    'createLesson replay вернул другой id'
  );

  const lessonDelRes = makeRes();
  await deleteLesson(
    {
      user: { userId: teacherId },
      params: { id: String(lessonRes1.body.id) },
    },
    lessonDelRes
  );
  assert(lessonDelRes.statusCode === 200, `deleteLesson статус ${lessonDelRes.statusCode}`);

  // -------- createReport idempotency --------
  const client = await pool.connect();
  let reportDate = lessonDate;
  try {
    const tz = await getUserTimeZone(client, teacherId);
    const today = getDateInTimeZoneISO(tz);
    reportDate = today;
    for (let i = 0; i < 30; i++) {
      const candidate = addDays(today, -i);
      const exists = await client.query(
        'SELECT 1 FROM reports WHERE created_by = $1 AND report_date = $2 LIMIT 1',
        [teacherId, candidate]
      );
      if (exists.rowCount === 0) {
        reportDate = candidate;
        break;
      }
    }
  } finally {
    client.release();
  }

  const reportKey = `smoke-report-${Date.now()}`;
  const reportReqBase = {
    user: { userId: teacherId },
    body: {
      report_date: reportDate,
      content: `${reportDate}\nsmoke report`,
    },
    headers: { 'idempotency-key': reportKey },
  };
  const reportRes1 = makeRes();
  await createReport(
    {
      ...reportReqBase,
      body: { ...reportReqBase.body },
      headers: { ...reportReqBase.headers },
    },
    reportRes1
  );
  assert(reportRes1.statusCode === 201, `createReport #1 статус ${reportRes1.statusCode}`);
  assert(reportRes1.body?.id, 'createReport #1 не вернул id');
  const reportRes2 = makeRes();
  await createReport(
    {
      ...reportReqBase,
      body: { ...reportReqBase.body },
      headers: { ...reportReqBase.headers },
    },
    reportRes2
  );
  assert(reportRes2.statusCode === 201, `createReport #2 статус ${reportRes2.statusCode}`);
  assert(
    Number(reportRes2.body?.id) === Number(reportRes1.body?.id),
    'createReport replay вернул другой id'
  );

  const reportDelRes = makeRes();
  await deleteReport(
    {
      user: { userId: teacherId },
      params: { id: String(reportRes1.body.id) },
    },
    reportDelRes
  );
  assert(reportDelRes.statusCode === 200, `deleteReport статус ${reportDelRes.statusCode}`);

  // -------- applyPayments idempotency --------
  const paymentKey = `smoke-payments-${Date.now()}`;
  const paymentBody = {
    payments: [
      {
        studentId,
        amount: 1.11,
        date: lessonDate,
        description: 'smoke payment',
      },
    ],
  };
  const payReq1 = {
    user: { userId: teacherId, email: 'smoke' },
    body: paymentBody,
    headers: { 'idempotency-key': paymentKey },
  };
  const payReq2 = {
    user: { userId: teacherId, email: 'smoke' },
    body: paymentBody,
    headers: { 'idempotency-key': paymentKey },
  };
  const payRes1 = makeRes();
  await applyPayments(payReq1, payRes1);
  assert(payRes1.statusCode === 200, `applyPayments #1 статус ${payRes1.statusCode}`);
  assert((payRes1.body?.success ?? 0) >= 1, 'applyPayments #1 не применил платеж');
  const payRes2 = makeRes();
  await applyPayments(payReq2, payRes2);
  assert(payRes2.statusCode === 200, `applyPayments #2 статус ${payRes2.statusCode}`);
  assert(
    JSON.stringify(payRes2.body) === JSON.stringify(payRes1.body),
    'applyPayments replay вернул другой payload'
  );

  const txIds = (payRes1.body?.results || [])
    .map((x) => x?.transaction?.id)
    .filter((x) => Number.isFinite(Number(x)));
  if (txIds.length > 0) {
    await pool.query('DELETE FROM transactions WHERE id = ANY($1::int[])', [txIds]);
  }

  console.log('✅ smoke-accounting-reliability: ok');
  await pool.end();
};

run().catch(async (error) => {
  console.error('❌ smoke-accounting-reliability failed:', error?.message || error);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});
