/**
 * Smoke: скрытая оценка работы преподавателей.
 *
 * Цель — гарантировать контракт:
 *  - admin-выгрузка содержит поля qualityIndex/qualityFactors/workProfile/
 *    expectedLessons/missedOnTypicalDowCount в teacherStats;
 *  - teacher-facing endpoints (reports.list, students.lessons, monthly salary)
 *    не отдают эти поля никаким образом (preview / list / details).
 *
 * Запуск: node scripts/smoke-accounting-hidden-quality.js
 */
import pool from '../db.js';
import { buildAccountingExport } from '../services/accounting/buildAccountingExport.js';
import {
  computeTeacherWorkProfile,
  expectedLessonsInPeriod,
  computeTeacherQuality,
} from '../services/accounting/teacherWorkProfile.js';
import { getReportsList } from '../controllers/reportsController.js';
import { getStudentLessons, getLessonsCalendarSummary } from '../controllers/lessonsController.js';
import { getMonthlySalaryReport } from '../controllers/reportsController.js';

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

const FORBIDDEN_KEYS = [
  'qualityIndex',
  'qualityFactors',
  'qualityReason',
  'workProfile',
  'expectedLessons',
  'missedOnTypicalDowCount',
  'typicalDows',
  'medianPerWorkDay',
];

const assertNoLeak = (label, body) => {
  if (body == null) return;
  const json = JSON.stringify(body);
  for (const key of FORBIDDEN_KEYS) {
    assert(
      !json.includes(`"${key}"`),
      `Утечка скрытой оценки: ключ "${key}" найден в ответе ${label}`
    );
  }
};

const run = async () => {
  const today = new Date();
  const isoToday = today.toISOString().slice(0, 10);
  const monthAgo = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);
  const isoFrom = monthAgo.toISOString().slice(0, 10);

  // 1) Admin payload содержит quality поля.
  const payload = await buildAccountingExport(pool, { from: isoFrom, to: isoToday });
  assert(Array.isArray(payload.teacherStats), 'payload.teacherStats должен быть массивом');

  for (const s of payload.teacherStats) {
    const hasQualityKey = Object.prototype.hasOwnProperty.call(s, 'qualityIndex');
    assert(hasQualityKey, `teacherStats[${s.teacherId}] не содержит qualityIndex`);
    assert(
      s.qualityIndex === null
        || (typeof s.qualityIndex === 'number' && s.qualityIndex >= 0 && s.qualityIndex <= 100),
      `teacherStats[${s.teacherId}].qualityIndex некорректен: ${s.qualityIndex}`
    );
    assert(Array.isArray(s.qualityFactors), `teacherStats[${s.teacherId}].qualityFactors не массив`);
    assert(
      Object.prototype.hasOwnProperty.call(s, 'workProfile'),
      `teacherStats[${s.teacherId}] не содержит workProfile`
    );
    assert(
      Object.prototype.hasOwnProperty.call(s, 'expectedLessons'),
      `teacherStats[${s.teacherId}] не содержит expectedLessons`
    );
    assert(
      Object.prototype.hasOwnProperty.call(s, 'missedOnTypicalDowCount'),
      `teacherStats[${s.teacherId}] не содержит missedOnTypicalDowCount`
    );

    for (const f of s.qualityFactors) {
      assert(typeof f.code === 'string' && f.code.length > 0, `qualityFactor без code: ${JSON.stringify(f)}`);
      assert(typeof f.delta === 'number', `qualityFactor без delta: ${JSON.stringify(f)}`);
    }
  }

  // 2) Профиль и индекс — детерминированный «недостаточно данных» для несуществующего преподавателя.
  const fakeProfile = await computeTeacherWorkProfile(pool, -999999, {
    anchorDate: isoFrom,
    lookbackDays: 84,
  });
  assert(fakeProfile.hasEnoughData === false, 'Профиль без истории должен hasEnoughData=false');
  assert(expectedLessonsInPeriod(fakeProfile, isoFrom, isoToday) === 0, 'expectedLessonsInPeriod без истории должен быть 0');
  const { qualityIndex } = computeTeacherQuality({}, fakeProfile);
  assert(qualityIndex === null, 'qualityIndex должен быть null при недостатке истории');

  // 3) Найдём активного teacher с реальными уроками за последние ~90 дней.
  const teacherWithLessons = await pool.query(
    `SELECT l.created_by AS teacher_id, ts.student_id
     FROM lessons l
     JOIN teacher_students ts ON ts.teacher_id = l.created_by
     WHERE l.created_by IS NOT NULL
       AND l.lesson_date >= (CURRENT_DATE - INTERVAL '90 days')
     ORDER BY l.lesson_date DESC
     LIMIT 1`
  );

  if (teacherWithLessons.rowCount === 0) {
    console.warn('Пропускаем teacher-facing проверки: нет teacher с lessons за 90 дней');
  } else {
    const teacherId = Number(teacherWithLessons.rows[0].teacher_id);
    const studentId = Number(teacherWithLessons.rows[0].student_id);

    const reportsRes = makeRes();
    await getReportsList(
      {
        user: { userId: teacherId },
        query: { date_from: isoFrom, date_to: isoToday },
      },
      reportsRes
    );
    assertNoLeak('GET /reports/list', reportsRes.body);

    const lessonsRes = makeRes();
    await getStudentLessons(
      {
        user: { userId: teacherId },
        params: { studentId: String(studentId) },
        query: {},
      },
      lessonsRes
    );
    assertNoLeak('GET /students/:studentId/lessons', lessonsRes.body);

    const calendarRes = makeRes();
    await getLessonsCalendarSummary(
      {
        user: { userId: teacherId },
        query: { from: isoFrom, to: isoToday },
      },
      calendarRes
    );
    assertNoLeak('GET /students/calendar-summary', calendarRes.body);

    const salaryRes = makeRes();
    await getMonthlySalaryReport(
      {
        user: { userId: teacherId },
        query: { year: String(today.getFullYear()), month: String(today.getMonth() + 1) },
      },
      salaryRes
    );
    assertNoLeak('GET /reports/monthly-salary', salaryRes.body);
  }

  // 4) Прямая повторная защита: dump full payload и убедимся, что top-level totals/lessons
  //    не несут скрытых полей (только teacherStats и vault Excel должны их содержать).
  const lessonsJson = JSON.stringify(payload.lessons || []);
  const totalsJson = JSON.stringify(payload.totals || {});
  for (const key of FORBIDDEN_KEYS) {
    assert(!lessonsJson.includes(`"${key}"`), `payload.lessons содержит запрещённый ключ ${key}`);
    assert(!totalsJson.includes(`"${key}"`), `payload.totals содержит запрещённый ключ ${key}`);
  }

  console.log('OK smoke-accounting-hidden-quality');
  await pool.end();
};

run().catch(async (error) => {
  console.error('FAIL smoke-accounting-hidden-quality:', error?.message || error);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});
