/**
 * Regression smoke tests for reports/lessons integrity fixes.
 *
 * Covers:
 * 1) owner updateReport with changed report_date recalculates reports.is_late
 * 2) deleteLesson is blocked for lessons linked to report_lessons
 * 3) invalid IDs for report/lesson mutations are rejected with 400
 * 4) text report create does not silently skip unknown students (returns 400)
 *
 * Run:
 *   node scripts/smoke-reports-regressions.js
 */
import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';
import { deleteLesson } from '../controllers/lessonsController.js';
import { createReport, deleteReport, updateReport } from '../controllers/reportsController.js';
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

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

const addDays = (isoDate, delta) => {
  const d = new Date(`${isoDate}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
};

const hasReportOnDate = async (teacherId, dateIso) => {
  const r = await pool.query(
    'SELECT 1 FROM reports WHERE created_by = $1 AND report_date = $2 LIMIT 1',
    [teacherId, dateIso]
  );
  return r.rowCount > 0;
};

const countReportsOnDate = async (teacherId, dateIso) => {
  const r = await pool.query(
    'SELECT COUNT(*)::int AS c FROM reports WHERE created_by = $1 AND report_date = $2',
    [teacherId, dateIso]
  );
  return Number(r.rows[0]?.c || 0);
};

const pickFreeReportDate = async (teacherId, baseDateIso, fromOffsetDays, toOffsetDays) => {
  for (let i = fromOffsetDays; i <= toOffsetDays; i++) {
    const candidate = addDays(baseDateIso, -i);
    const busy = await hasReportOnDate(teacherId, candidate);
    if (!busy) return candidate;
  }
  return null;
};

const findOwnerCandidate = async () => {
  const linksRes = await pool.query(
    `SELECT DISTINCT ts.teacher_id, ts.student_id
     FROM teacher_students ts
     ORDER BY ts.teacher_id ASC, ts.student_id ASC`
  );
  assert(linksRes.rowCount > 0, 'Нет связок teacher_students для smoke-теста');

  const usersRes = await pool.query(
    `SELECT id, email
     FROM users
     ORDER BY id ASC`
  );
  const usersById = new Map(
    usersRes.rows.map((u) => [
      Number(u.id),
      {
        userId: Number(u.id),
        email: (u.email || '').toString(),
        username: (u.email || '').toString(),
      },
    ])
  );

  for (const row of linksRes.rows) {
    const teacherId = Number(row.teacher_id);
    const studentId = Number(row.student_id);
    const ownerUser = usersById.get(teacherId);
    if (!ownerUser || isSuperuser(ownerUser)) continue;

    const client = await pool.connect();
    let todayIso;
    try {
      const tz = await getUserTimeZone(client, teacherId);
      todayIso = getDateInTimeZoneISO(tz);
    } finally {
      client.release();
    }

    const freeToday = !(await hasReportOnDate(teacherId, todayIso));
    if (!freeToday) continue;

    const freePast = await pickFreeReportDate(teacherId, todayIso, 1, 60);
    if (!freePast) continue;

    return {
      ownerUser,
      ownerUserId: teacherId,
      ownerStudentId: studentId,
      todayIso,
      freePastDate: freePast,
    };
  }

  throw new Error(
    'Не найден не-суперпользователь с доступным today/past окном для smoke-regressions. Проверьте тестовые данные.'
  );
};

const run = async () => {
  const { ownerUser, ownerUserId, ownerStudentId, todayIso, freePastDate } = await findOwnerCandidate();

  let reportId1 = null;
  let reportId2 = null;
  try {
    // 0) Invalid IDs must fail fast with 400.
    const badUpdateRes = makeRes();
    await updateReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: 'abc' },
        body: {
          report_date: todayIso,
          slots: [
            {
              timeStart: '09:00',
              timeEnd: '10:00',
              students: [{ studentId: ownerStudentId, price: 1100, status: 'attended' }],
            },
          ],
        },
      },
      badUpdateRes
    );
    assert(badUpdateRes.statusCode === 400, `updateReport invalid id статус ${badUpdateRes.statusCode}, ожидался 400`);

    const badDeleteLessonRes = makeRes();
    await deleteLesson(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: 'abc' },
      },
      badDeleteLessonRes
    );
    assert(
      badDeleteLessonRes.statusCode === 400,
      `deleteLesson invalid id статус ${badDeleteLessonRes.statusCode}, ожидался 400`
    );

    // 0.1) Text report must not silently skip unknown student rows.
    const textDate = await pickFreeReportDate(ownerUserId, todayIso, 0, 60);
    assert(textDate, 'Не найдена свободная дата для текстового отчета с неизвестным учеником');
    const beforeCount = await countReportsOnDate(ownerUserId, textDate);
    const unknownStudentName = `SmokeUnknownStudent_${Date.now()}`;
    const createTextRes = makeRes();
    await createReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        body: {
          report_date: textDate,
          content: `${textDate}\n\n09-10 ${unknownStudentName} 1.2`,
        },
        headers: { 'idempotency-key': `smoke-regression-text-${Date.now()}` },
      },
      createTextRes
    );
    assert(
      createTextRes.statusCode === 400,
      `createReport(text unknown student) статус ${createTextRes.statusCode}, ожидался 400`
    );
    const afterCount = await countReportsOnDate(ownerUserId, textDate);
    assert(afterCount === beforeCount, 'Неуспешный text create не должен оставлять запись reports');

    // 1) Owner updateReport with changed report_date must recalc is_late.
    const createRes1 = makeRes();
    await createReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        body: {
          report_date: todayIso,
          slots: [
            {
              timeStart: '09:00',
              timeEnd: '10:00',
              students: [{ studentId: ownerStudentId, price: 1100, status: 'attended' }],
            },
          ],
        },
        headers: { 'idempotency-key': `smoke-regression-create-1-${Date.now()}` },
      },
      createRes1
    );
    assert(createRes1.statusCode === 201, `createReport#1 статус ${createRes1.statusCode}`);
    reportId1 = Number(createRes1.body?.id);
    assert(Number.isFinite(reportId1), 'createReport#1 не вернул report.id');
    assert(createRes1.body?.is_late === false, 'Новый отчет за today должен быть is_late=false');

    const ownerUpdateRes = makeRes();
    await updateReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(reportId1) },
        body: {
          report_date: freePastDate,
          slots: [
            {
              timeStart: '09:15',
              timeEnd: '10:15',
              students: [{ studentId: ownerStudentId, price: 1200, status: 'attended' }],
            },
          ],
        },
      },
      ownerUpdateRes
    );
    assert(ownerUpdateRes.statusCode === 200, `owner updateReport статус ${ownerUpdateRes.statusCode}`);
    assert(ownerUpdateRes.body?.is_late === true, 'owner updateReport должен вернуть is_late=true после сдвига даты в прошлое');

    const dbLateCheck = await pool.query(
      'SELECT report_date::text AS report_date, is_late FROM reports WHERE id = $1',
      [reportId1]
    );
    assert(dbLateCheck.rowCount === 1, 'Не найден обновленный отчет для проверки is_late');
    assert(dbLateCheck.rows[0].report_date === freePastDate, 'report_date в БД не обновился');
    assert(dbLateCheck.rows[0].is_late === true, 'is_late в БД не пересчитался для owner update');

    // 2) deleteLesson must reject lessons linked to reports.
    const reportDate2 = await pickFreeReportDate(ownerUserId, todayIso, 0, 60);
    assert(reportDate2, 'Не найдена свободная дата для сценария linked lesson delete');

    const createRes2 = makeRes();
    await createReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        body: {
          report_date: reportDate2,
          slots: [
            {
              timeStart: '11:00',
              timeEnd: '12:00',
              students: [{ studentId: ownerStudentId, price: 1300, status: 'attended' }],
            },
          ],
        },
        headers: { 'idempotency-key': `smoke-regression-create-2-${Date.now()}` },
      },
      createRes2
    );
    assert(createRes2.statusCode === 201, `createReport#2 статус ${createRes2.statusCode}`);
    reportId2 = Number(createRes2.body?.id);
    assert(Number.isFinite(reportId2), 'createReport#2 не вернул report.id');
    const linkedLessonId = Number(createRes2.body?.lessons?.[0]?.id);
    assert(Number.isFinite(linkedLessonId), 'createReport#2 не вернул linked lesson id');

    const deleteLinkedRes = makeRes();
    await deleteLesson(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(linkedLessonId) },
      },
      deleteLinkedRes
    );
    assert(deleteLinkedRes.statusCode === 409, `deleteLesson linked статус ${deleteLinkedRes.statusCode}, ожидался 409`);
    assert(
      typeof deleteLinkedRes.body?.message === 'string' &&
        deleteLinkedRes.body.message.includes('привязанное к отчету'),
      'Ожидалось понятное сообщение о блокировке удаления linked lesson'
    );

    const lessonStillExists = await pool.query('SELECT 1 FROM lessons WHERE id = $1', [linkedLessonId]);
    assert(lessonStillExists.rowCount === 1, 'Связанное занятие не должно удаляться при 409');

    console.log('✅ smoke-reports-regressions: ok');
  } finally {
    if (reportId2) {
      const cleanup2 = makeRes();
      await deleteReport(
        {
          user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
          params: { id: String(reportId2) },
        },
        cleanup2
      );
      assert(cleanup2.statusCode === 200, `cleanup report#2 статус ${cleanup2.statusCode}`);
    }
    if (reportId1) {
      const cleanup1 = makeRes();
      await deleteReport(
        {
          user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
          params: { id: String(reportId1) },
        },
        cleanup1
      );
      assert(cleanup1.statusCode === 200, `cleanup report#1 статус ${cleanup1.statusCode}`);
    }
    await pool.end();
  }
};

run().catch(async (error) => {
  console.error('❌ smoke-reports-regressions failed:', error?.message || error);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});
