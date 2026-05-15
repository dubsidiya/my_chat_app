/**
 * Edge-case smoke tests for accounting/reporting.
 *
 * Run:
 *   node scripts/smoke-accounting-edge-cases.js
 */
import pool from '../db.js';
import { createLesson, deleteLesson } from '../controllers/lessonsController.js';
import { createReport } from '../controllers/reportsController.js';
import { getMakeupPendingSummary } from '../controllers/studentsController.js';
import { isSuperuser } from '../middleware/auth.js';

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

  // 3) superuser может удалить чужое занятие (и связанная lesson-транзакция удаляется).
  const usersRes = await pool.query('SELECT id, email FROM users ORDER BY id ASC');
  const users = usersRes.rows.map((u) => ({
    userId: Number(u.id),
    email: (u.email || '').toString(),
    username: (u.email || '').toString(),
  }));
  const superUser = users.find((u) => isSuperuser(u)) || null;

  if (superUser) {
    const links = await pool.query(
      `SELECT DISTINCT ts.teacher_id, ts.student_id
       FROM teacher_students ts
       ORDER BY ts.teacher_id ASC, ts.student_id ASC`
    );
    const ownerLink = links.rows
      .map((r) => ({
        teacherId: Number(r.teacher_id),
        studentId: Number(r.student_id),
      }))
      .find((x) => x.teacherId !== superUser.userId && !isSuperuser({
        userId: x.teacherId,
        email: users.find((u) => u.userId === x.teacherId)?.email || '',
        username: users.find((u) => u.userId === x.teacherId)?.username || '',
      }));

    if (!ownerLink) {
      console.warn('⚠️  Пропущено: superuser delete чужого занятия (нет подходящего owner-link)');
    } else {
      const now2 = new Date();
      const lessonDate2 = now2.toISOString().slice(0, 10);
      const hh2 = String((now2.getUTCHours() + 6) % 24).padStart(2, '0');
      const mm2 = String((now2.getUTCMinutes() + 19) % 60).padStart(2, '0');
      const lessonTime2 = `${hh2}:${mm2}`;

      const foreignCreateRes = makeRes();
      await createLesson(
        {
          user: { userId: ownerLink.teacherId, email: users.find((u) => u.userId === ownerLink.teacherId)?.email || '' },
          params: { studentId: String(ownerLink.studentId) },
          body: {
            lesson_date: lessonDate2,
            lesson_time: lessonTime2,
            duration_minutes: 60,
            price: 888,
            notes: 'super-delete-foreign',
          },
          headers: { 'idempotency-key': `super-foreign-${Date.now()}` },
        },
        foreignCreateRes
      );
      assert(foreignCreateRes.statusCode === 201, `create foreign lesson статус ${foreignCreateRes.statusCode}`);
      const foreignLessonId = Number(foreignCreateRes.body?.id);
      assert(Number.isFinite(foreignLessonId), 'foreign createLesson не вернул id');

      const txBefore = await pool.query(
        'SELECT COUNT(*)::int AS cnt FROM transactions WHERE lesson_id = $1',
        [foreignLessonId]
      );
      assert((txBefore.rows[0]?.cnt ?? 0) >= 1, 'Перед удалением не найдена lesson-транзакция');

      const superDeleteRes = makeRes();
      await deleteLesson(
        {
          user: { userId: superUser.userId, email: superUser.email, username: superUser.username },
          params: { id: String(foreignLessonId) },
        },
        superDeleteRes
      );
      assert(superDeleteRes.statusCode === 200, `superuser deleteLesson статус ${superDeleteRes.statusCode}`);

      const lessonAfter = await pool.query('SELECT 1 FROM lessons WHERE id = $1', [foreignLessonId]);
      assert(lessonAfter.rowCount === 0, 'После удаления занятие осталось в lessons');
      const txAfter = await pool.query(
        'SELECT COUNT(*)::int AS cnt FROM transactions WHERE lesson_id = $1',
        [foreignLessonId]
      );
      assert((txAfter.rows[0]?.cnt ?? 0) === 0, 'После удаления остались transactions.lesson_id на удалённый урок');
    }
  } else {
    console.warn('⚠️  Пропущено: superuser delete чужого занятия (нет superuser в окружении)');
  }

  // 4) Платная отмена в день входит в «к отработке» (открытый долг, не «пропуски − отработки»).
  const now3 = new Date();
  const lessonDate3 = now3.toISOString().slice(0, 10);
  const hh3a = String((now3.getUTCHours() + 8) % 24).padStart(2, '0');
  const mm3a = String((now3.getUTCMinutes() + 23) % 60).padStart(2, '0');
  const hh3b = String((now3.getUTCHours() + 9) % 24).padStart(2, '0');
  const mm3b = String((now3.getUTCMinutes() + 29) % 60).padStart(2, '0');
  const freeCancelRes = makeRes();
  await createLesson(
    {
      user: { userId: teacherId },
      params: { studentId: String(studentId) },
      body: {
        lesson_date: lessonDate3,
        lesson_time: `${hh3a}:${mm3a}`,
        duration_minutes: 60,
        price: 998,
        status: 'cancel_same_day',
        notes: 'smoke-free-cancel',
      },
      headers: { 'idempotency-key': `free-cancel-${Date.now()}` },
    },
    freeCancelRes
  );
  assert(freeCancelRes.statusCode === 201, `free cancel статус ${freeCancelRes.statusCode}`);
  const freeCancelLessonId = Number(freeCancelRes.body?.id);

  const paidCancelRes = makeRes();
  await createLesson(
    {
      user: { userId: teacherId },
      params: { studentId: String(studentId) },
      body: {
        lesson_date: lessonDate3,
        lesson_time: `${hh3b}:${mm3b}`,
        duration_minutes: 60,
        price: 999,
        status: 'cancel_same_day',
        notes: 'smoke-paid-cancel-makeup-debt',
      },
      headers: { 'idempotency-key': `paid-cancel-${Date.now()}` },
    },
    paidCancelRes
  );
  assert(paidCancelRes.statusCode === 201, `paid cancel_same_day статус ${paidCancelRes.statusCode}`);
  const paidCancelLessonId = Number(paidCancelRes.body?.id);
  assert(paidCancelRes.body?.is_chargeable === true, 'вторая отмена должна быть chargeable');

  const pendingRes = makeRes();
  await getMakeupPendingSummary({ user: { userId: teacherId } }, pendingRes);
  assert(pendingRes.statusCode === 200, `makeup-pending статус ${pendingRes.statusCode}`);
  const item = (pendingRes.body?.items || []).find((x) => Number(x.studentId) === Number(studentId));
  assert(item, 'ученик должен быть в makeup-pending');
  assert(
    Number(item.openCancelCount ?? 0) >= 2,
    `ожидали openCancelCount >= 2 (бесплатная + платная), получили ${item.openCancelCount}`
  );

  for (const lessonId of [paidCancelLessonId, freeCancelLessonId]) {
    if (Number.isFinite(lessonId)) {
      await deleteLesson(
        { user: { userId: teacherId }, params: { id: String(lessonId) } },
        makeRes()
      );
    }
  }

  console.log('✅ smoke-accounting-edge-cases: ok');
  await pool.end();
};

run().catch(async (error) => {
  console.error('❌ smoke-accounting-edge-cases failed:', error?.message || error);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});
