import pool from '../db.js';

const isValidISODate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);

const toNumber = (v) => {
  if (v == null) return 0;
  const n = typeof v === 'number' ? v : parseFloat(v.toString());
  return Number.isFinite(n) ? n : 0;
};

const asCsv = (rows) => {
  const escape = (v) => {
    const s = (v ?? '').toString();
    if (s.includes('"') || s.includes(',') || s.includes('\n') || s.includes('\r')) {
      return `"${s.replace(/"/g, '""')}"`;
    }
    return s;
  };
  return rows.map((r) => r.map(escape).join(',')).join('\n');
};

// GET /admin/accounting/export?from=YYYY-MM-DD&to=YYYY-MM-DD&format=json|csv
export const exportAccounting = async (req, res) => {
  try {
    const from = (req.query.from || '').toString();
    const to = (req.query.to || '').toString();
    const format = ((req.query.format || 'json').toString() || 'json').toLowerCase();

    if (!isValidISODate(from) || !isValidISODate(to)) {
      return res.status(400).json({ message: 'Параметры from/to обязательны в формате YYYY-MM-DD' });
    }

    if (to < from) {
      return res.status(400).json({ message: 'to должен быть >= from' });
    }

    // 1) Преподаватели
    const teachersRes = await pool.query('SELECT id, email FROM users ORDER BY email');
    const teacherById = new Map(teachersRes.rows.map((r) => [r.id, r.email]));

    // 2) Связи преподаватель-ученик
    const linksRes = await pool.query(
      `SELECT ts.teacher_id, ts.student_id, u.email as teacher_username
       FROM teacher_students ts
       JOIN users u ON u.id = ts.teacher_id`
    );
    const studentTeachers = new Map(); // studentId -> [{teacherId, teacherUsername}]
    for (const row of linksRes.rows) {
      const sid = row.student_id;
      if (!studentTeachers.has(sid)) studentTeachers.set(sid, []);
      studentTeachers.get(sid).push({ teacherId: row.teacher_id, teacherUsername: row.teacher_username });
    }

    // 3) Ученики
    const studentsRes = await pool.query(
      `SELECT id, name, parent_name, phone, email
       FROM students
       ORDER BY name, id`
    );
    const studentById = new Map(studentsRes.rows.map((s) => [s.id, s]));

    // 4) Кредит (депозиты/рефанды) по ученикам на конец периода
    // created_at <= (to + 1 day) 00:00
    const creditsRes = await pool.query(
      `SELECT student_id,
              COALESCE(SUM(CASE WHEN type IN ('deposit','refund') THEN amount ELSE 0 END), 0) as credit
       FROM transactions
       WHERE created_at < ($1::date + interval '1 day')
       GROUP BY student_id`,
      [to]
    );
    const creditByStudent = new Map(creditsRes.rows.map((r) => [r.student_id, toNumber(r.credit)]));

    // 5) Депозиты за период (для справки бухгалтерии)
    const depositsPeriodRes = await pool.query(
      `SELECT student_id,
              COALESCE(SUM(amount), 0) as deposits
       FROM transactions
       WHERE type = 'deposit'
         AND created_at >= $1::date
         AND created_at < ($2::date + interval '1 day')
       GROUP BY student_id`,
      [from, to]
    );
    const depositsInPeriodByStudent = new Map(
      depositsPeriodRes.rows.map((r) => [r.student_id, toNumber(r.deposits)])
    );

    // 6) Все занятия до конца периода (нужно для FIFO-распределения оплат)
    const lessonsRes = await pool.query(
      `SELECT l.id,
              l.student_id,
              l.lesson_date,
              l.lesson_time,
              l.duration_minutes,
              l.price,
              l.notes,
              l.created_by as teacher_id,
              u.email as teacher_username
       FROM lessons l
       JOIN users u ON u.id = l.created_by
       WHERE l.lesson_date <= $1::date
       ORDER BY l.student_id, l.lesson_date, l.lesson_time NULLS LAST, l.created_at, l.id`,
      [to]
    );

    const lessonsByStudent = new Map(); // studentId -> lessons[]
    for (const l of lessonsRes.rows) {
      const sid = l.student_id;
      if (!lessonsByStudent.has(sid)) lessonsByStudent.set(sid, []);
      lessonsByStudent.get(sid).push(l);
    }

    // FIFO распределение кредитов по занятиям до конца периода
    const coverageByLessonId = new Map(); // lessonId -> {paid, unpaid}
    const remainingCreditByStudent = new Map();
    const debtByStudent = new Map();

    for (const student of studentsRes.rows) {
      const sid = student.id;
      let credit = creditByStudent.get(sid) || 0;
      const lessons = lessonsByStudent.get(sid) || [];
      let debt = 0;

      for (const lesson of lessons) {
        const price = toNumber(lesson.price);
        const paid = Math.max(0, Math.min(credit, price));
        const unpaid = Math.max(0, price - paid);
        credit = credit - paid;
        debt += unpaid;
        coverageByLessonId.set(lesson.id, { paid, unpaid });
      }

      remainingCreditByStudent.set(sid, credit);
      debtByStudent.set(sid, debt);
    }

    // Формируем плоский список уроков за период + агрегаты по преподавателям
    const lessonsInPeriod = [];
    const teacherAgg = new Map(); // teacherId -> {teacherId, teacherUsername, lessonsCount, amount, paid, unpaid}

    for (const l of lessonsRes.rows) {
      const d = (l.lesson_date || '').toString().slice(0, 10);
      if (d < from || d > to) continue;
      const cov = coverageByLessonId.get(l.id) || { paid: 0, unpaid: toNumber(l.price) };
      const st = studentById.get(l.student_id);
      const row = {
        lessonId: l.id,
        studentId: l.student_id,
        studentName: st?.name || '',
        lessonDate: d,
        lessonTime: l.lesson_time ? l.lesson_time.toString().slice(0, 5) : null,
        durationMinutes: l.duration_minutes,
        price: toNumber(l.price),
        paidAmount: cov.paid,
        unpaidAmount: cov.unpaid,
        isPaid: cov.unpaid <= 0.000001,
        teacherId: l.teacher_id,
        teacherUsername: l.teacher_username || teacherById.get(l.teacher_id) || '',
        notes: l.notes || null,
      };
      lessonsInPeriod.push(row);

      const key = l.teacher_id;
      if (!teacherAgg.has(key)) {
        teacherAgg.set(key, {
          teacherId: key,
          teacherUsername: row.teacherUsername,
          lessonsCount: 0,
          amount: 0,
          paidAmount: 0,
          unpaidAmount: 0,
        });
      }
      const a = teacherAgg.get(key);
      a.lessonsCount += 1;
      a.amount += row.price;
      a.paidAmount += row.paidAmount;
      a.unpaidAmount += row.unpaidAmount;
    }

    // Ученики с деталями (для бухгалтерии удобно)
    const studentsOut = studentsRes.rows.map((s) => ({
      id: s.id,
      name: s.name,
      parentName: s.parent_name || null,
      phone: s.phone || null,
      email: s.email || null,
      teachers: studentTeachers.get(s.id) || [],
      depositsInPeriod: depositsInPeriodByStudent.get(s.id) || 0,
      debtAsOfTo: debtByStudent.get(s.id) || 0,
      prepaidAsOfTo: remainingCreditByStudent.get(s.id) || 0,
    }));

    const teacherOut = [...teacherAgg.values()].sort((a, b) => (a.teacherUsername || '').localeCompare(b.teacherUsername || ''));

    // Дерево: преподаватель -> дети -> занятия (с paid/unpaid)
    const treeByTeacher = new Map(); // teacherId -> {teacherId, teacherUsername, students: Map}
    for (const l of lessonsInPeriod) {
      const tid = l.teacherId;
      if (!treeByTeacher.has(tid)) {
        treeByTeacher.set(tid, {
          teacherId: tid,
          teacherUsername: l.teacherUsername,
          students: new Map(), // studentId -> {studentId, studentName, lessons: []}
        });
      }
      const tNode = treeByTeacher.get(tid);
      if (!tNode.students.has(l.studentId)) {
        tNode.students.set(l.studentId, {
          studentId: l.studentId,
          studentName: l.studentName,
          lessons: [],
        });
      }
      tNode.students.get(l.studentId).lessons.push({
        lessonId: l.lessonId,
        lessonDate: l.lessonDate,
        lessonTime: l.lessonTime,
        durationMinutes: l.durationMinutes,
        price: l.price,
        paidAmount: l.paidAmount,
        unpaidAmount: l.unpaidAmount,
        isPaid: l.isPaid,
        notes: l.notes,
      });
    }

    const tree = [...treeByTeacher.values()]
      .map((t) => ({
        teacherId: t.teacherId,
        teacherUsername: t.teacherUsername,
        students: [...t.students.values()].sort((a, b) => (a.studentName || '').localeCompare(b.studentName || '')),
      }))
      .sort((a, b) => (a.teacherUsername || '').localeCompare(b.teacherUsername || ''));

    const payload = {
      period: { from, to },
      totals: {
        lessonsCount: lessonsInPeriod.length,
        lessonsAmount: lessonsInPeriod.reduce((acc, x) => acc + x.price, 0),
        paidAmount: lessonsInPeriod.reduce((acc, x) => acc + x.paidAmount, 0),
        unpaidAmount: lessonsInPeriod.reduce((acc, x) => acc + x.unpaidAmount, 0),
      },
      teachers: teacherOut,
      students: studentsOut,
      lessons: lessonsInPeriod,
      tree,
    };

    if (format === 'csv') {
      const header = [
        'lesson_id',
        'lesson_date',
        'lesson_time',
        'teacher_username',
        'student_id',
        'student_name',
        'price',
        'paid_amount',
        'unpaid_amount',
        'is_paid',
      ];
      const rows = [header];
      for (const l of lessonsInPeriod) {
        rows.push([
          l.lessonId,
          l.lessonDate,
          l.lessonTime || '',
          l.teacherUsername || '',
          l.studentId,
          l.studentName || '',
          l.price,
          l.paidAmount,
          l.unpaidAmount,
          l.isPaid ? 'yes' : 'no',
        ]);
      }
      const csv = asCsv(rows);
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', `attachment; filename="accounting_${from}_${to}.csv"`);
      return res.status(200).send(csv);
    }

    return res.json(payload);
  } catch (error) {
    console.error('Ошибка выгрузки бухгалтерии:', error);
    return res.status(500).json({ message: 'Ошибка выгрузки бухгалтерии' });
  }
};

