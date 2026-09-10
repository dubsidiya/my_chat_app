/**
 * Edge-case smoke tests for accounting/reporting.
 *
 * Run:
 *   node scripts/smoke-accounting-edge-cases.js
 */
import bcrypt from 'bcryptjs';
import pool from '../db.js';
import { deleteAccount } from '../controllers/authController.js';
import { createLesson, deleteLesson } from '../controllers/lessonsController.js';
import { createReport } from '../controllers/reportsController.js';
import { createStudent, deleteStudentFull, getAllStudents, getMakeupPendingSummary, getStudentBalance, updateStudent } from '../controllers/studentsController.js';
import { isSuperuser } from '../middleware/auth.js';
import {
  accountingFootprintBlocksDelete,
  loadAccountingFootprint,
} from '../utils/accountDeletionGuard.js';

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

  const makeupIdx = await pool.query(
    `SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'ux_lessons_makeup_origin'`
  );
  assert(
    makeupIdx.rowCount === 1,
    'Нет индекса ux_lessons_makeup_origin — примените migrations/add_lessons_makeup_origin_unique.sql'
  );

  const missTime = `${String((now.getUTCHours() + 5) % 24).padStart(2, '0')}:${String((now.getUTCMinutes() + 21) % 60).padStart(2, '0')}`;
  const makeupTimeA = `${String((now.getUTCHours() + 5) % 24).padStart(2, '0')}:${String((now.getUTCMinutes() + 23) % 60).padStart(2, '0')}`;
  const makeupTimeB = `${String((now.getUTCHours() + 5) % 24).padStart(2, '0')}:${String((now.getUTCMinutes() + 25) % 60).padStart(2, '0')}`;
  assert(makeupTimeA !== makeupTimeB, 'времена отработок для гонки должны отличаться');

  let missId = null;
  const createdMakeupIds = [];
  try {
    const missRes = makeRes();
    await createLesson(
      {
        user: { userId: teacherId },
        params: { studentId: String(studentId) },
        body: {
          lesson_date: lessonDate,
          lesson_time: missTime,
          duration_minutes: 60,
          price: 777,
          status: 'missed',
          notes: 'parallel-makeup-origin-miss',
        },
        headers: { 'idempotency-key': `parallel-miss-${Date.now()}` },
      },
      missRes
    );
    assert(missRes.statusCode === 201, `create miss для гонки отработки статус ${missRes.statusCode}`);
    missId = Number(missRes.body?.id);
    assert(Number.isFinite(missId), 'create miss не вернул id');

    const makeupReq = {
      user: { userId: teacherId },
      params: { studentId: String(studentId) },
      body: {
        lesson_date: lessonDate,
        duration_minutes: 60,
        price: 777,
        status: 'makeup',
        origin_lesson_id: missId,
      },
    };
    const m1 = makeRes();
    const m2 = makeRes();
    await Promise.all([
      createLesson(
        {
          ...makeupReq,
          body: { ...makeupReq.body, lesson_time: makeupTimeA, notes: 'parallel-makeup-a' },
          headers: { 'idempotency-key': `parallel-makeup-a-${Date.now()}` },
        },
        m1
      ),
      createLesson(
        {
          ...makeupReq,
          body: { ...makeupReq.body, lesson_time: makeupTimeB, notes: 'parallel-makeup-b' },
          headers: { 'idempotency-key': `parallel-makeup-b-${Date.now()}` },
        },
        m2
      ),
    ]);
    const makeupStatuses = [m1.statusCode, m2.statusCode].sort((a, b) => a - b);
    assert(
      makeupStatuses.includes(201) && (makeupStatuses.includes(400) || makeupStatuses.includes(409)),
      `Ожидались 201 и 400/409 для гонки отработки, получили ${makeupStatuses.join(',')}`
    );
    const makeupCount = await pool.query(
      `SELECT COUNT(*)::int AS cnt FROM lessons WHERE status = 'makeup' AND origin_lesson_id = $1`,
      [missId]
    );
    assert(Number(makeupCount.rows[0]?.cnt) === 1, 'гонка не должна создать две отработки на один пропуск');
    const makeupLoser = m1.statusCode === 201 ? m2 : m1;
    if (makeupLoser.statusCode === 400) {
      assert(
        typeof makeupLoser.body?.message === 'string' && makeupLoser.body.message.includes('уже отработан'),
        'проигравшая гонка отработки должна говорить, что пропуск уже отработан'
      );
    }
    for (const res of [m1, m2]) {
      const id = Number(res.body?.id);
      if (res.statusCode === 201 && Number.isFinite(id)) createdMakeupIds.push(id);
    }
  } finally {
    for (const id of createdMakeupIds) {
      await deleteLesson({ user: { userId: teacherId }, params: { id: String(id) } }, makeRes());
    }
    if (missId) {
      await deleteLesson({ user: { userId: teacherId }, params: { id: String(missId) } }, makeRes());
    }
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

  // H4) Частичный PUT /students/:id не сбрасывает pay_by_bank_transfer и контакты.
  const stamp = Date.now();
  const originalPhone = `+7999${String(stamp).slice(-7)}`;
  const originalEmail = `h4-${stamp}@smoke.local`;
  let patchStudentId = null;
  try {
    const createStudentRes = makeRes();
    await createStudent(
      {
        user: { userId: teacherId },
        body: {
          name: `smoke-h4-partial-${stamp}`,
          parent_name: 'H4 Parent',
          phone: originalPhone,
          email: originalEmail,
          notes: 'h4-keep-me',
          pay_by_bank_transfer: true,
        },
        headers: { 'idempotency-key': `smoke-h4-create-${stamp}` },
      },
      createStudentRes
    );
    assert(
      createStudentRes.statusCode === 200 || createStudentRes.statusCode === 201,
      `createStudent для H4 статус ${createStudentRes.statusCode}`
    );
    patchStudentId = Number(createStudentRes.body?.id);
    assert(Number.isFinite(patchStudentId), 'createStudent для H4 не вернул id');
    assert(
      String(createStudentRes.body?.name || '').startsWith('smoke-h4-partial-'),
      'createStudent склеил существующего ученика — H4-смоук прерван'
    );
    assert(createStudentRes.body?.pay_by_bank_transfer === true, 'новый ученик должен быть с pay_by_bank_transfer=true');
    const renamed = `smoke-h4-renamed-${stamp}`;
    const nameOnlyRes = makeRes();
    await updateStudent(
      {
        user: { userId: teacherId },
        params: { id: String(patchStudentId) },
        body: { name: renamed },
      },
      nameOnlyRes
    );
    assert(nameOnlyRes.statusCode === 200, `частичный PUT имя статус ${nameOnlyRes.statusCode}`);
    assert(nameOnlyRes.body?.name === renamed, 'имя должно обновиться');
    assert(nameOnlyRes.body?.pay_by_bank_transfer === true, 'частичный PUT не должен сбрасывать pay_by_bank_transfer');
    assert(nameOnlyRes.body?.parent_name === 'H4 Parent', 'частичный PUT не должен обнулять parent_name');
    assert(nameOnlyRes.body?.phone === originalPhone, 'частичный PUT не должен обнулять phone');
    assert(nameOnlyRes.body?.email === originalEmail, 'частичный PUT не должен обнулять email');
    assert(nameOnlyRes.body?.notes === 'h4-keep-me', 'частичный PUT не должен обнулять notes');

    const flagOnlyRes = makeRes();
    await updateStudent(
      {
        user: { userId: teacherId },
        params: { id: String(patchStudentId) },
        body: { pay_by_bank_transfer: false },
      },
      flagOnlyRes
    );
    assert(flagOnlyRes.statusCode === 200, `частичный PUT pay_by_bank_transfer статус ${flagOnlyRes.statusCode}`);
    assert(flagOnlyRes.body?.pay_by_bank_transfer === false, 'явный false должен снимать pay_by_bank_transfer');
    assert(flagOnlyRes.body?.name === renamed, 'смена флага оплаты не должна трогать имя');
    assert(flagOnlyRes.body?.parent_name === 'H4 Parent', 'смена флага оплаты не должна трогать контакты');
  } finally {
    if (patchStudentId) {
      const owned = await pool.query(
        `SELECT name FROM students WHERE id = $1 AND name LIKE 'smoke-h4-%'`,
        [patchStudentId]
      );
      if (owned.rowCount === 1) {
        await pool.query('DELETE FROM teacher_students WHERE student_id = $1', [patchStudentId]);
        await pool.query('DELETE FROM students WHERE id = $1', [patchStudentId]);
      }
    }
  }

  const otherUsers = await pool.query(
    `SELECT id, email FROM users WHERE id <> $1 ORDER BY id ASC`,
    [teacherId]
  );
  const teacherB = otherUsers.rows
    .map((u) => ({
      userId: Number(u.id),
      email: (u.email || '').toString(),
      username: (u.email || '').toString(),
    }))
    .find((u) => !isSuperuser(u));
  if (!teacherB) {
    console.warn('⚠️  Пропущено: H5 shared-deposit (нет второго не-суперпользователя)');
  } else {
    const stamp5 = Date.now();
    let h5StudentId = null;
    try {
      const createH5 = makeRes();
      await createStudent(
        {
          user: { userId: teacherId },
          body: {
            name: `smoke-h5-shared-${stamp5}`,
            phone: `+7988${String(stamp5).slice(-7)}`,
          },
          headers: { 'idempotency-key': `smoke-h5-create-${stamp5}` },
        },
        createH5
      );
      assert(createH5.statusCode === 200 || createH5.statusCode === 201, `createStudent H5 статус ${createH5.statusCode}`);
      h5StudentId = Number(createH5.body?.id);
      assert(Number.isFinite(h5StudentId), 'createStudent H5 не вернул id');
      assert(
        String(createH5.body?.name || '').startsWith('smoke-h5-shared-'),
        'createStudent H5 склеил существующего ученика'
      );
      await pool.query(
        `INSERT INTO teacher_students (teacher_id, student_id)
         VALUES ($1, $2)
         ON CONFLICT (teacher_id, student_id) DO NOTHING`,
        [teacherB.userId, h5StudentId]
      );
      await pool.query(
        `INSERT INTO transactions (student_id, amount, type, description, created_by, target_teacher_id)
         VALUES ($1, 10000, 'deposit', 'smoke-h5-unallocated', $2, NULL)`,
        [h5StudentId, teacherId]
      );
      await pool.query(
        `INSERT INTO transactions (student_id, amount, type, description, created_by)
         VALUES ($1, 10000, 'lesson', 'smoke-h5-lesson-a', $2)`,
        [h5StudentId, teacherId]
      );

      const aAfterA = makeRes();
      await getStudentBalance(
        { user: { userId: teacherId }, params: { id: String(h5StudentId) }, query: {} },
        aAfterA
      );
      const bAfterA = makeRes();
      await getStudentBalance(
        { user: { userId: teacherB.userId, email: teacherB.email, username: teacherB.username }, params: { id: String(h5StudentId) }, query: {} },
        bAfterA
      );
      assert(aAfterA.statusCode === 200, `баланс A после своего урока ${aAfterA.statusCode}`);
      assert(bAfterA.statusCode === 200, `баланс B после урока A ${bAfterA.statusCode}`);
      assert(Math.abs(Number(aAfterA.body?.balance) - 0) < 0.01, `A должен видеть 0, получил ${aAfterA.body?.balance}`);
      assert(
        Math.abs(Number(bAfterA.body?.balance) - 0) < 0.01,
        `B не должен видеть чужой неадресный депозит как +10000 после списания A, получил ${bAfterA.body?.balance}`
      );

      await pool.query(
        `INSERT INTO transactions (student_id, amount, type, description, created_by)
         VALUES ($1, 10000, 'lesson', 'smoke-h5-lesson-b', $2)`,
        [h5StudentId, teacherB.userId]
      );
      const aAfterBoth = makeRes();
      await getStudentBalance(
        { user: { userId: teacherId }, params: { id: String(h5StudentId) }, query: {} },
        aAfterBoth
      );
      const bAfterBoth = makeRes();
      await getStudentBalance(
        { user: { userId: teacherB.userId, email: teacherB.email, username: teacherB.username }, params: { id: String(h5StudentId) }, query: {} },
        bAfterBoth
      );
      assert(Math.abs(Number(aAfterBoth.body?.balance) + 5000) < 0.01, `A после двух списаний должен видеть -5000, получил ${aAfterBoth.body?.balance}`);
      assert(Math.abs(Number(bAfterBoth.body?.balance) + 5000) < 0.01, `B после двух списаний должен видеть -5000, получил ${bAfterBoth.body?.balance}`);

      const listA = makeRes();
      await getAllStudents({ user: { userId: teacherId } }, listA);
      assert(listA.statusCode === 200, `getAllStudents A статус ${listA.statusCode}`);
      const rowA = (listA.body || []).find((s) => Number(s.id) === h5StudentId);
      assert(rowA, 'ученик H5 должен быть в списке преподавателя A');
      assert(Math.abs(Number(rowA.balance) + 5000) < 0.01, `список A: баланс ${rowA.balance}, ожидали -5000`);
    } finally {
      if (h5StudentId) {
        const owned = await pool.query(
          `SELECT name FROM students WHERE id = $1 AND name LIKE 'smoke-h5-%'`,
          [h5StudentId]
        );
        if (owned.rowCount === 1) {
          await pool.query('DELETE FROM transactions WHERE student_id = $1', [h5StudentId]);
          await pool.query('DELETE FROM teacher_students WHERE student_id = $1', [h5StudentId]);
          await pool.query('DELETE FROM students WHERE id = $1', [h5StudentId]);
        }
      }
    }
  }

  // H7) Полное удаление отключено: 410, занятия и транзакции на месте.
  const beforeFull = await pool.query(
    `SELECT
       (SELECT COUNT(*)::int FROM lessons WHERE student_id = $1) AS lessons,
       (SELECT COUNT(*)::int FROM transactions WHERE student_id = $1) AS txs
     FROM students WHERE id = $1`,
    [studentId]
  );
  assert(beforeFull.rowCount === 1, 'seed-ученик должен существовать до H7');
  const fullRes = makeRes();
  await deleteStudentFull(
    { user: { userId: teacherId }, params: { id: String(studentId) } },
    fullRes
  );
  assert(fullRes.statusCode === 410, `полное удаление должно быть 410, получили ${fullRes.statusCode}`);
  const afterFull = await pool.query(
    `SELECT
       (SELECT COUNT(*)::int FROM lessons WHERE student_id = $1) AS lessons,
       (SELECT COUNT(*)::int FROM transactions WHERE student_id = $1) AS txs
     FROM students WHERE id = $1`,
    [studentId]
  );
  assert(afterFull.rowCount === 1, 'ученик не должен исчезнуть после отключённого full delete');
  assert(
    Number(afterFull.rows[0].lessons) === Number(beforeFull.rows[0].lessons),
    'занятия не должны каскадиться'
  );
  assert(
    Number(afterFull.rows[0].txs) === Number(beforeFull.rows[0].txs),
    'транзакции не должны каскадиться'
  );

  // H8) Самоудаление с бухгалтерским следом — 409; без следа — аккаунт можно удалить.
  const seedFootprint = await loadAccountingFootprint(pool, teacherId);
  assert(accountingFootprintBlocksDelete(seedFootprint), 'у seed-преподавателя должен быть бухгалтерский след');

  const h8Stamp = Date.now();
  const h8Password = 'SmokeH8-pass!';
  const h8Hash = await bcrypt.hash(h8Password, 4);
  let h8BlockUserId = null;
  let h8OkUserId = null;
  let h8StudentId = null;
  try {
    const blockUser = await pool.query(
      `INSERT INTO users (email, password)
       VALUES ($1, $2)
       RETURNING id`,
      [`smoke-h8-block-${h8Stamp}@test.local`, h8Hash]
    );
    h8BlockUserId = blockUser.rows[0].id;
    const h8Student = await pool.query(
      `INSERT INTO students (name, created_by)
       VALUES ($1, $2)
       RETURNING id`,
      [`smoke-h8-${h8Stamp}`, h8BlockUserId]
    );
    h8StudentId = h8Student.rows[0].id;

    const blockedRes = makeRes();
    await deleteAccount(
      {
        user: { userId: h8BlockUserId },
        params: { userId: String(h8BlockUserId) },
        body: { password: h8Password },
      },
      blockedRes
    );
    assert(blockedRes.statusCode === 409, `аккаунт с учеником должен быть 409, получили ${blockedRes.statusCode}`);
    const stillThere = await pool.query('SELECT id FROM users WHERE id = $1', [h8BlockUserId]);
    assert(stillThere.rowCount === 1, 'пользователь с бухгалтерским следом не должен удалиться');
    const studentStill = await pool.query('SELECT id FROM students WHERE id = $1', [h8StudentId]);
    assert(studentStill.rowCount === 1, 'ученик не должен каскадиться при 409');

    const okUser = await pool.query(
      `INSERT INTO users (email, password)
       VALUES ($1, $2)
       RETURNING id`,
      [`smoke-h8-ok-${h8Stamp}@test.local`, h8Hash]
    );
    h8OkUserId = okUser.rows[0].id;
    const okRes = makeRes();
    await deleteAccount(
      {
        user: { userId: h8OkUserId },
        params: { userId: String(h8OkUserId) },
        body: { password: h8Password },
      },
      okRes
    );
    assert(okRes.statusCode === 200, `пустой аккаунт должен удалиться, получили ${okRes.statusCode}`);
    const okGone = await pool.query('SELECT id FROM users WHERE id = $1', [h8OkUserId]);
    assert(okGone.rowCount === 0, 'пустой аккаунт должен быть удалён');
    h8OkUserId = null;
  } finally {
    if (h8StudentId) {
      const owned = await pool.query(
        `SELECT id FROM students WHERE id = $1 AND name LIKE 'smoke-h8-%'`,
        [h8StudentId]
      );
      if (owned.rowCount === 1) {
        await pool.query('DELETE FROM teacher_students WHERE student_id = $1', [h8StudentId]);
        await pool.query('DELETE FROM students WHERE id = $1', [h8StudentId]);
      }
    }
    if (h8BlockUserId) {
      const ownedUser = await pool.query(
        `SELECT id FROM users WHERE id = $1 AND email LIKE 'smoke-h8-%'`,
        [h8BlockUserId]
      );
      if (ownedUser.rowCount === 1) {
        await pool.query('DELETE FROM users WHERE id = $1', [h8BlockUserId]);
      }
    }
    if (h8OkUserId) {
      const ownedOk = await pool.query(
        `SELECT id FROM users WHERE id = $1 AND email LIKE 'smoke-h8-%'`,
        [h8OkUserId]
      );
      if (ownedOk.rowCount === 1) {
        await pool.query('DELETE FROM users WHERE id = $1', [h8OkUserId]);
      }
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
