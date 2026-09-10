/**
 * Regression smoke tests for reports/lessons integrity fixes.
 *
 * Covers:
 * 1) owner updateReport: same-date edit keeps is_late; moving date into the past marks late;
 *    moving a late report onto today cannot clear is_late
 * 2) rebuild of a missed report keeps origin_lesson_id of an existing makeup
 * 3) deleteLesson is blocked for lessons linked to report_lessons
 * 4) invalid IDs for report/lesson mutations are rejected with 400
 * 5) text report create does not silently skip unknown students (returns 400)
 * 6) structured report slots are stored sorted by lesson time
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
  let reportIdMiss = null;
  let reportIdMakeup = null;
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

    // 0.2) Slots sent out of chronological order must be stored sorted by time.
    const sortDate = await pickFreeReportDate(ownerUserId, todayIso, 0, 60);
    assert(sortDate, 'Не найдена свободная дата для проверки сортировки слотов');
    const createSortRes = makeRes();
    await createReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        body: {
          report_date: sortDate,
          slots: [
            {
              timeStart: '14:00',
              timeEnd: '15:00',
              students: [{ studentId: ownerStudentId, price: 1500, status: 'attended' }],
            },
            {
              timeStart: '12:00',
              timeEnd: '13:00',
              students: [{ studentId: ownerStudentId, price: 1500, status: 'attended' }],
            },
          ],
        },
        headers: { 'idempotency-key': `smoke-regression-sort-${Date.now()}` },
      },
      createSortRes
    );
    assert(createSortRes.statusCode === 201, `createReport(sort slots) статус ${createSortRes.statusCode}`);
    const reportIdSort = Number(createSortRes.body?.id);
    assert(Number.isFinite(reportIdSort), 'createReport(sort slots) не вернул report.id');
    const contentLines = String(createSortRes.body?.content || '')
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => /^\d{1,2}:\d{2}-\d{1,2}:\d{2}\s/.test(line));
    assert(contentLines.length === 2, 'Ожидалось 2 строки занятий в content');
    assert(contentLines[0].startsWith('12:00-'), `Первое занятие должно быть 12:00, получено: ${contentLines[0]}`);
    assert(contentLines[1].startsWith('14:00-'), `Второе занятие должно быть 14:00, получено: ${contentLines[1]}`);
    const cleanupSort = makeRes();
    await deleteReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(reportIdSort) },
      },
      cleanupSort
    );
    assert(cleanupSort.statusCode === 200, `cleanup sort report статус ${cleanupSort.statusCode}`);

    // 1.0) Создание отчёта сразу на прошлую дату — is_late=true при create.
    const createPastRes = makeRes();
    await createReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        body: {
          report_date: freePastDate,
          slots: [
            {
              timeStart: '10:00',
              timeEnd: '11:00',
              students: [{ studentId: ownerStudentId, price: 1400, status: 'attended' }],
            },
          ],
        },
        headers: { 'idempotency-key': `smoke-regression-create-past-${Date.now()}` },
      },
      createPastRes
    );
    assert(createPastRes.statusCode === 201, `createReport(past) статус ${createPastRes.statusCode}`);
    const reportIdPast = Number(createPastRes.body?.id);
    assert(Number.isFinite(reportIdPast), 'createReport(past) не вернул report.id');
    assert(
      createPastRes.body?.is_late === true,
      'Отчёт с report_date в прошлом должен быть is_late=true при создании'
    );
    const cleanupPast = makeRes();
    await deleteReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(reportIdPast) },
      },
      cleanupPast
    );
    assert(cleanupPast.statusCode === 200, `cleanup past report статус ${cleanupPast.statusCode}`);

    // 1) Owner updateReport: правка без смены даты не трогает is_late;
    //    перенос на прошлую дату делает отчёт поздним; перенос позднего на сегодня не снимает флаг.
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

    const sameDateUpdateRes = makeRes();
    await updateReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(reportId1) },
        body: {
          report_date: todayIso,
          slots: [
            {
              timeStart: '09:05',
              timeEnd: '10:05',
              students: [{ studentId: ownerStudentId, price: 1150, status: 'attended' }],
            },
          ],
        },
      },
      sameDateUpdateRes
    );
    assert(sameDateUpdateRes.statusCode === 200, `same-date updateReport статус ${sameDateUpdateRes.statusCode}`);
    assert(
      sameDateUpdateRes.body?.is_late === false,
      'правка без смены даты не должна ставить is_late=true'
    );

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
    assert(
      ownerUpdateRes.body?.is_late === true,
      'перенос вовремя сданного отчёта на прошлую дату должен ставить is_late=true'
    );

    const dbLateCheck = await pool.query(
      'SELECT report_date::text AS report_date, is_late FROM reports WHERE id = $1',
      [reportId1]
    );
    assert(dbLateCheck.rowCount === 1, 'Не найден обновленный отчет для проверки is_late');
    assert(dbLateCheck.rows[0].report_date === freePastDate, 'report_date в БД не обновился');
    assert(dbLateCheck.rows[0].is_late === true, 'is_late в БД должен стать true после переноса даты в прошлое');

    const incomeAfterBackdate = await pool.query(
      `SELECT COALESCE(SUM(amount), 0)::float8 AS total
       FROM teacher_balance_transactions
       WHERE type = 'lesson_income' AND report_id = $1`,
      [reportId1]
    );
    assert(
      Number(incomeAfterBackdate.rows[0]?.total || 0) === 0,
      'поздний отчёт после переноса даты не должен давать lesson_income'
    );

    const moveBackToTodayRes = makeRes();
    await updateReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(reportId1) },
        body: {
          report_date: todayIso,
          slots: [
            {
              timeStart: '09:20',
              timeEnd: '10:20',
              students: [{ studentId: ownerStudentId, price: 1250, status: 'attended' }],
            },
          ],
        },
      },
      moveBackToTodayRes
    );
    assert(moveBackToTodayRes.statusCode === 200, `updateReport back to today статус ${moveBackToTodayRes.statusCode}`);
    assert(
      moveBackToTodayRes.body?.is_late === true,
      'перенос позднего отчёта на сегодня не должен снимать is_late'
    );

    // H2) Пересборка отчёта с пропуском не должна рвать origin_lesson_id внешней отработки.
    const missDate = await pickFreeReportDate(ownerUserId, todayIso, 1, 60);
    assert(missDate, 'Не найдена свободная дата для сценария makeup origin');
    const createMissRes = makeRes();
    await createReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        body: {
          report_date: missDate,
          slots: [
            {
              timeStart: '12:00',
              timeEnd: '13:00',
              students: [{ studentId: ownerStudentId, price: 1500, status: 'missed' }],
            },
          ],
        },
        headers: { 'idempotency-key': `smoke-regression-create-miss-${Date.now()}` },
      },
      createMissRes
    );
    assert(createMissRes.statusCode === 201, `createReport(miss) статус ${createMissRes.statusCode}`);
    reportIdMiss = Number(createMissRes.body?.id);
    assert(Number.isFinite(reportIdMiss), 'createReport(miss) не вернул report.id');
    const missLessonId = Number(createMissRes.body?.lessons?.[0]?.id);
    assert(Number.isFinite(missLessonId), 'createReport(miss) не вернул lesson id');

    const makeupDate = await pickFreeReportDate(ownerUserId, todayIso, 1, 60);
    assert(makeupDate, 'Не найдена свободная дата для отработки');
    const createMakeupRes = makeRes();
    await createReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        body: {
          report_date: makeupDate,
          slots: [
            {
              timeStart: '12:00',
              timeEnd: '13:00',
              students: [{
                studentId: ownerStudentId,
                price: 1500,
                status: 'makeup',
                originLessonId: missLessonId,
              }],
            },
          ],
        },
        headers: { 'idempotency-key': `smoke-regression-create-makeup-${Date.now()}` },
      },
      createMakeupRes
    );
    assert(createMakeupRes.statusCode === 201, `createReport(makeup) статус ${createMakeupRes.statusCode}`);
    reportIdMakeup = Number(createMakeupRes.body?.id);
    assert(Number.isFinite(reportIdMakeup), 'createReport(makeup) не вернул report.id');
    const makeupLessonId = Number(createMakeupRes.body?.lessons?.[0]?.id);
    assert(Number.isFinite(makeupLessonId), 'createReport(makeup) не вернул lesson id');
    const linkBefore = await pool.query(
      'SELECT origin_lesson_id FROM lessons WHERE id = $1',
      [makeupLessonId]
    );
    assert(Number(linkBefore.rows[0]?.origin_lesson_id) === missLessonId, 'отработка должна ссылаться на пропуск');

    const rebuildMissRes = makeRes();
    await updateReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(reportIdMiss) },
        body: {
          report_date: missDate,
          slots: [
            {
              timeStart: '12:00',
              timeEnd: '13:00',
              students: [{ studentId: ownerStudentId, price: 1600, status: 'missed' }],
            },
          ],
        },
      },
      rebuildMissRes
    );
    assert(rebuildMissRes.statusCode === 200, `rebuild miss report статус ${rebuildMissRes.statusCode}`);
    const missAfterRebuild = await pool.query(
      'SELECT id, status FROM lessons WHERE id = $1',
      [missLessonId]
    );
    assert(missAfterRebuild.rowCount === 1, 'id пропуска должен сохраниться после пересборки отчёта');
    assert(missAfterRebuild.rows[0].status === 'missed', 'статус пропуска должен остаться missed');
    const linkAfterRebuild = await pool.query(
      'SELECT origin_lesson_id FROM lessons WHERE id = $1',
      [makeupLessonId]
    );
    assert(
      Number(linkAfterRebuild.rows[0]?.origin_lesson_id) === missLessonId,
      'пересборка отчёта с пропуском не должна обнулять origin_lesson_id отработки'
    );

    const dupMakeupDate = await pickFreeReportDate(ownerUserId, todayIso, 1, 60);
    assert(dupMakeupDate, 'Не найдена свободная дата для повторной отработки');
    const dupMakeupRes = makeRes();
    await createReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        body: {
          report_date: dupMakeupDate,
          slots: [
            {
              timeStart: '14:00',
              timeEnd: '15:00',
              students: [{
                studentId: ownerStudentId,
                price: 1500,
                status: 'makeup',
                originLessonId: missLessonId,
              }],
            },
          ],
        },
        headers: { 'idempotency-key': `smoke-regression-dup-makeup-${Date.now()}` },
      },
      dupMakeupRes
    );
    assert(dupMakeupRes.statusCode === 400, `повторная отработка статус ${dupMakeupRes.statusCode}, ожидался 400`);
    if (dupMakeupRes.statusCode === 201 && dupMakeupRes.body?.id) {
      const dupCleanup = makeRes();
      await deleteReport(
        {
          user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
          params: { id: String(dupMakeupRes.body.id) },
        },
        dupCleanup
      );
    }

    const convertMissRes = makeRes();
    await updateReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(reportIdMiss) },
        body: {
          report_date: missDate,
          slots: [
            {
              timeStart: '12:00',
              timeEnd: '13:00',
              students: [{ studentId: ownerStudentId, price: 1600, status: 'attended' }],
            },
          ],
        },
      },
      convertMissRes
    );
    assert(
      convertMissRes.statusCode === 409,
      `перевод отработанного пропуска в attended статус ${convertMissRes.statusCode}, ожидался 409`
    );
    const linkAfterConvert = await pool.query(
      'SELECT origin_lesson_id FROM lessons WHERE id = $1',
      [makeupLessonId]
    );
    assert(
      Number(linkAfterConvert.rows[0]?.origin_lesson_id) === missLessonId,
      'отклонённая правка не должна рвать связь пропуск→отработка'
    );

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
    if (reportIdMakeup) {
      const cleanupMakeup = makeRes();
      await deleteReport(
        {
          user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
          params: { id: String(reportIdMakeup) },
        },
        cleanupMakeup
      );
      assert(cleanupMakeup.statusCode === 200, `cleanup makeup report статус ${cleanupMakeup.statusCode}`);
    }
    if (reportIdMiss) {
      const cleanupMiss = makeRes();
      await deleteReport(
        {
          user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
          params: { id: String(reportIdMiss) },
        },
        cleanupMiss
      );
      assert(cleanupMiss.statusCode === 200, `cleanup miss report статус ${cleanupMiss.statusCode}`);
    }
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
