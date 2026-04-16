/**
 * Smoke-check report edit permissions:
 * 1) author can update own report
 * 2) superuser can update чужой report
 * 3) non-owner (not superuser) cannot update чужой report
 *
 * Run:
 *   node scripts/smoke-reports-permissions.js
 */
import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';
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

const pickFreeReportDate = async (teacherId) => {
  const client = await pool.connect();
  try {
    const tz = await getUserTimeZone(client, teacherId);
    const today = getDateInTimeZoneISO(tz);
    for (let i = 0; i < 45; i++) {
      const candidate = addDays(today, -i);
      const exists = await client.query(
        'SELECT 1 FROM reports WHERE created_by = $1 AND report_date = $2 LIMIT 1',
        [teacherId, candidate]
      );
      if (exists.rowCount === 0) return candidate;
    }
    throw new Error('Не удалось найти свободную дату для тестового отчета');
  } finally {
    client.release();
  }
};

const run = async () => {
  const links = await pool.query(
    `SELECT DISTINCT ts.teacher_id, ts.student_id
     FROM teacher_students ts
     ORDER BY ts.teacher_id ASC, ts.student_id ASC`
  );
  assert(links.rowCount > 0, 'Нет данных teacher_students для smoke-теста');

  const usersRes = await pool.query(
    `SELECT id, email
     FROM users
     ORDER BY id ASC`
  );
  const users = usersRes.rows.map((u) => ({
    userId: Number(u.id),
    email: (u.email || '').toString(),
    username: (u.email || '').toString(),
  }));
  assert(users.length > 0, 'Нет пользователей для smoke-теста');

  const linksWithFlags = links.rows.map((r) => ({
    teacherId: Number(r.teacher_id),
    studentId: Number(r.student_id),
    super: isSuperuser({
      userId: Number(r.teacher_id),
      email: users.find((u) => u.userId === Number(r.teacher_id))?.email || '',
      username: users.find((u) => u.userId === Number(r.teacher_id))?.username || '',
    }),
  }));

  // Предпочтительно берём владельца-не-суперпользователя, чтобы "супер редактирует чужой"
  // был именно отдельным сценарием. Если такого нет — берём любую доступную связку.
  const ownerLink = linksWithFlags.find((x) => !x.super) || linksWithFlags[0];
  const ownerUserId = ownerLink.teacherId;
  const ownerStudentId = ownerLink.studentId;
  const ownerUser = users.find((u) => u.userId === ownerUserId);
  assert(ownerUser, 'Не найден владелец отчёта в users');

  const superUser = users.find((u) => isSuperuser(u) && u.userId !== ownerUserId) || null;

  const superUserId = superUser?.userId;
  const nonOwnerUser = users.find(
    (u) => u.userId !== ownerUserId && u.userId !== superUserId && !isSuperuser(u)
  ) || users.find((u) => u.userId !== ownerUserId && !isSuperuser(u)) || null;

  const reportDate = await pickFreeReportDate(ownerUserId);

  const createReq = {
    user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
    body: {
      report_date: reportDate,
      slots: [
        {
          timeStart: '10:00',
          timeEnd: '11:00',
          students: [
            {
              studentId: ownerStudentId,
              price: 1200,
              status: 'attended',
            },
          ],
        },
      ],
    },
    headers: { 'idempotency-key': `smoke-report-perms-create-${Date.now()}` },
  };

  const createRes = makeRes();
  await createReport(createReq, createRes);
  assert(createRes.statusCode === 201, `createReport статус ${createRes.statusCode}`);
  const reportId = Number(createRes.body?.id);
  assert(Number.isFinite(reportId), 'createReport не вернул report.id');

  try {
    // 1) Владелец может редактировать
    const ownerUpdateRes = makeRes();
    await updateReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(reportId) },
        body: {
          report_date: reportDate,
          slots: [
            {
              timeStart: '10:30',
              timeEnd: '11:30',
              students: [
                {
                  studentId: ownerStudentId,
                  price: 1300,
                  status: 'attended',
                },
              ],
            },
          ],
        },
      },
      ownerUpdateRes
    );
    assert(ownerUpdateRes.statusCode === 200, `owner update статус ${ownerUpdateRes.statusCode}`);

    // 2) Суперпользователь может редактировать чужой отчёт
    if (superUser) {
      const superUpdateRes = makeRes();
      await updateReport(
        {
          user: { userId: superUser.userId, email: superUser.email, username: superUser.username },
          params: { id: String(reportId) },
          body: {
            report_date: reportDate,
            slots: [
              {
                timeStart: '11:00',
                timeEnd: '12:00',
                students: [
                  {
                    studentId: ownerStudentId,
                    price: 1400,
                    status: 'attended',
                  },
                ],
              },
            ],
          },
        },
        superUpdateRes
      );
      assert(superUpdateRes.statusCode === 200, `superuser update статус ${superUpdateRes.statusCode}`);
    } else {
      console.warn('⚠️  Пропущено: сценарий superuser update (нет отдельного superuser в окружении)');
    }

    // 3) Обычный не-владелец не может редактировать чужой отчёт
    if (nonOwnerUser) {
      const nonOwnerUpdateRes = makeRes();
      await updateReport(
        {
          user: { userId: nonOwnerUser.userId, email: nonOwnerUser.email, username: nonOwnerUser.username },
          params: { id: String(reportId) },
          body: {
            report_date: reportDate,
            slots: [
              {
                timeStart: '12:00',
                timeEnd: '13:00',
                students: [
                  {
                    studentId: ownerStudentId,
                    price: 1500,
                    status: 'attended',
                  },
                ],
              },
            ],
          },
        },
        nonOwnerUpdateRes
      );
      assert(
        nonOwnerUpdateRes.statusCode === 404,
        `non-owner update должен вернуть 404, получили ${nonOwnerUpdateRes.statusCode}`
      );
    } else {
      console.warn('⚠️  Пропущено: сценарий non-owner denied (нет подходящего non-owner пользователя)');
    }
  } finally {
    const delRes = makeRes();
    await deleteReport(
      {
        user: { userId: ownerUserId, email: ownerUser.email, username: ownerUser.username },
        params: { id: String(reportId) },
      },
      delRes
    );
    assert(delRes.statusCode === 200, `cleanup deleteReport статус ${delRes.statusCode}`);
  }

  console.log('✅ smoke-reports-permissions: ok');
  await pool.end();
};

run().catch(async (error) => {
  console.error('❌ smoke-reports-permissions failed:', error?.message || error);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});

