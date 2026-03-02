/**
 * Edge-case smoke tests for accounting/reporting.
 *
 * Run:
 *   node scripts/smoke-accounting-edge-cases.js
 */
import pool from '../db.js';
import { createLesson, deleteLesson } from '../controllers/lessonsController.js';
import { createReport } from '../controllers/reportsController.js';

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
  const seed = await pool.query(
    `SELECT ts.teacher_id, ts.student_id
     FROM teacher_students ts
     ORDER BY ts.created_at DESC
     LIMIT 1`
  );
  assert(seed.rowCount > 0, 'Нет teacher_students для edge-case теста');
  const teacherId = seed.rows[0].teacher_id;
  const studentId = seed.rows[0].student_id;

  // 1) Параллельный дубль урока -> один success, второй 409.
  const now = new Date();
  const lessonDate = now.toISOString().slice(0, 10);
  const hh = String((now.getUTCHours() + 4) % 24).padStart(2, '0');
  const mm = String((now.getUTCMinutes() + 13) % 60).padStart(2, '0');
  const lessonTime = `${hh}:${mm}`;
  const baseReq = {
    user: { userId: teacherId },
    params: { studentId: String(studentId) },
    body: {
      lesson_date: lessonDate,
      lesson_time: lessonTime,
      duration_minutes: 60,
      price: 777,
      notes: 'parallel-edge',
    },
  };
  const r1 = makeRes();
  const r2 = makeRes();
  await Promise.all([
    createLesson(
      { ...baseReq, headers: { 'idempotency-key': `parallel-a-${Date.now()}` } },
      r1
    ),
    createLesson(
      { ...baseReq, headers: { 'idempotency-key': `parallel-b-${Date.now()}` } },
      r2
    ),
  ]);
  const statuses = [r1.statusCode, r2.statusCode].sort();
  assert(statuses[0] === 201 || statuses[0] === 409, `Неожиданные статусы урока: ${statuses.join(',')}`);
  assert(statuses[1] === 409 || statuses[1] === 201, `Неожиданные статусы урока: ${statuses.join(',')}`);
  assert(statuses.includes(201) && statuses.includes(409), `Ожидались 201 и 409, получили ${statuses.join(',')}`);
  const createdLessonId = r1.statusCode === 201 ? r1.body?.id : r2.body?.id;
  if (createdLessonId) {
    await deleteLesson(
      { user: { userId: teacherId }, params: { id: String(createdLessonId) } },
      makeRes()
    );
  }

  // 2) Некорректная дата отчета должна давать 400.
  const badReportRes = makeRes();
  await createReport(
    {
      user: { userId: teacherId },
      body: {
        report_date: '2026/01/01',
        content: 'bad-date',
      },
      headers: { 'idempotency-key': `bad-report-${Date.now()}` },
    },
    badReportRes
  );
  assert(badReportRes.statusCode === 400, `Ожидался 400 для bad report_date, получили ${badReportRes.statusCode}`);

  console.log('✅ smoke-accounting-edge-cases: ok');
  await pool.end();
};

run().catch(async (error) => {
  console.error('❌ smoke-accounting-edge-cases failed:', error?.message || error);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});
