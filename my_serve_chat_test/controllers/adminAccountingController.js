import pool from '../db.js';
import { sqlUserAccountingName, sqlUserAccountingNameOrEmpty } from '../utils/userAccountingDisplaySql.js';

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

const toIsoDate = (v) => {
  if (!v) return '';
  if (typeof v === 'string') {
    // pg может вернуть 'YYYY-MM-DD' или 'YYYY-MM-DDTHH:MM:SS...'
    if (v.length >= 10) return v.slice(0, 10);
    return v;
  }
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  // fallback
  try {
    return new Date(v).toISOString().slice(0, 10);
  } catch (_) {
    return '';
  }
};

const walletKey = (studentId, teacherId) => `${studentId}:${teacherId}`;

// GET /admin/accounting/export?from=YYYY-MM-DD&to=YYYY-MM-DD&format=json|csv
export const exportAccounting = async (req, res) => {
  try {
    const from = (req.query.from || '').toString();
    const to = (req.query.to || '').toString();
    const formatRaw = ((req.query.format || 'json').toString() || 'json').toLowerCase();
    const format = formatRaw === 'csv' ? 'csv' : 'json';
    const bankTransferOnly = req.query.bank_transfer_only === '1' || req.query.bank_transfer_only === 'true';

    if (!isValidISODate(from) || !isValidISODate(to)) {
      return res.status(400).json({ message: 'Параметры from/to обязательны в формате YYYY-MM-DD' });
    }

    if (to < from) {
      return res.status(400).json({ message: 'to должен быть >= from' });
    }

    // 1) Преподаватели
    const teachersRes = await pool.query(
      `SELECT id, email, display_name,
              ${sqlUserAccountingName('u')} AS accounting_name
       FROM users u
       ORDER BY accounting_name`
    );
    const teacherById = new Map(teachersRes.rows.map((r) => [r.id, r.accounting_name || r.email || '']));

    // 2) Связи преподаватель-ученик
    const linksRes = await pool.query(
      `SELECT ts.teacher_id, ts.student_id, ${sqlUserAccountingName('u')} AS teacher_username
       FROM teacher_students ts
       JOIN users u ON u.id = ts.teacher_id`
    );
    const studentTeachers = new Map(); // studentId -> [{teacherId, teacherUsername}]
    for (const row of linksRes.rows) {
      const sid = row.student_id;
      if (!studentTeachers.has(sid)) studentTeachers.set(sid, []);
      studentTeachers.get(sid).push({ teacherId: row.teacher_id, teacherUsername: row.teacher_username });
    }

    // 3) Ученики (в т.ч. способ оплаты: наличные / расчётный счёт)
    const studentsRes = await pool.query(
      `SELECT id, name, parent_name, phone, email,
              COALESCE(pay_by_bank_transfer, false) as pay_by_bank_transfer
       FROM students
       ORDER BY name, id`
    );
    const studentById = new Map(studentsRes.rows.map((s) => [s.id, s]));
    const studentIdsBankTransfer = new Set(
      studentsRes.rows.filter((s) => s.pay_by_bank_transfer === true).map((s) => s.id)
    );

    // 4) Кредит (депозиты/рефанды) на конец периода:
    // - адресные: по кошелькам ученик+преподаватель
    // - legacy неадресные (target_teacher_id IS NULL): общий пул ученика
    // created_at <= (to + 1 day) 00:00
    const creditsRes = await pool.query(
      `SELECT student_id,
              target_teacher_id AS teacher_id,
              COALESCE(SUM(CASE WHEN type IN ('deposit','refund') THEN amount ELSE 0 END), 0) as credit
       FROM transactions
       WHERE created_at < ($1::date + interval '1 day')
       GROUP BY student_id, target_teacher_id`,
      [to]
    );
    const creditByWallet = new Map();
    const unallocatedCreditByStudent = new Map();
    for (const r of creditsRes.rows) {
      const amount = toNumber(r.credit);
      if (r.teacher_id == null) {
        unallocatedCreditByStudent.set(r.student_id, amount);
      } else {
        creditByWallet.set(walletKey(r.student_id, r.teacher_id), amount);
      }
    }

    // 5) Депозиты за период (для справки бухгалтерии)
    const depositsPeriodRes = await pool.query(
      `SELECT student_id,
              target_teacher_id AS teacher_id,
              COALESCE(SUM(amount), 0) as deposits
       FROM transactions
       WHERE type = 'deposit'
         AND created_at >= $1::date
         AND created_at < ($2::date + interval '1 day')
       GROUP BY student_id, target_teacher_id`,
      [from, to]
    );
    const depositsInPeriodByWallet = new Map();
    const unallocatedDepositsInPeriodByStudent = new Map();
    for (const r of depositsPeriodRes.rows) {
      const amount = toNumber(r.deposits);
      if (r.teacher_id == null) {
        unallocatedDepositsInPeriodByStudent.set(r.student_id, amount);
      } else {
        depositsInPeriodByWallet.set(walletKey(r.student_id, r.teacher_id), amount);
      }
    }

    // 6) Все занятия до конца периода (нужно для FIFO-распределения оплат)
    const lessonsRes = await pool.query(
      `SELECT l.id,
              l.student_id,
              l.lesson_date,
              l.lesson_time,
              l.duration_minutes,
              l.price,
              l.status,
              COALESCE(l.is_chargeable, true) as is_chargeable,
              l.origin_lesson_id,
              o.lesson_date AS origin_lesson_date,
              l.notes,
              l.created_by as teacher_id,
              ${sqlUserAccountingName('u')} AS teacher_username
       FROM lessons l
       LEFT JOIN lessons o ON o.id = l.origin_lesson_id
       LEFT JOIN users u ON u.id = l.created_by
       WHERE l.lesson_date <= $1::date
       ORDER BY l.student_id, l.lesson_date, l.lesson_time NULLS LAST, l.created_at, l.id`,
      [to]
    );

    const lessonsByWallet = new Map(); // studentId:teacherId -> lessons[]
    for (const l of lessonsRes.rows) {
      const key = walletKey(l.student_id, l.teacher_id);
      if (!lessonsByWallet.has(key)) lessonsByWallet.set(key, []);
      lessonsByWallet.get(key).push(l);
    }

    // debug: диапазон дат в уроках до конца периода
    let minLessonDate = null;
    let maxLessonDate = null;
    for (const l of lessonsRes.rows) {
      const d = toIsoDate(l.lesson_date);
      if (!d) continue;
      if (!minLessonDate || d < minLessonDate) minLessonDate = d;
      if (!maxLessonDate || d > maxLessonDate) maxLessonDate = d;
    }

    // FIFO распределение кредитов по занятиям до конца периода
    const coverageByLessonId = new Map(); // lessonId -> {paid, unpaid}
    const remainingCreditByWallet = new Map();
    const remainingUnallocatedCreditByStudent = new Map(unallocatedCreditByStudent);
    const remainingCreditByStudent = new Map();
    const debtByStudent = new Map();
    const teachersByStudent = new Map(); // studentId -> Set(teacherId)
    for (const row of linksRes.rows) {
      if (!teachersByStudent.has(row.student_id)) teachersByStudent.set(row.student_id, new Set());
      teachersByStudent.get(row.student_id).add(row.teacher_id);
    }

    for (const [key, lessons] of lessonsByWallet.entries()) {
      const [sidRaw, tidRaw] = key.split(':');
      const sid = Number(sidRaw);
      const tid = Number(tidRaw);
      let credit = creditByWallet.get(key) || 0;
      let debt = 0;

      for (const lesson of lessons) {
        const price = toNumber(lesson.price);
        const paid = Math.max(0, Math.min(credit, price));
        const unpaid = Math.max(0, price - paid);
        credit = credit - paid;
        debt += unpaid;
        coverageByLessonId.set(lesson.id, { paid, unpaid });
      }

      remainingCreditByWallet.set(key, credit);
      remainingCreditByStudent.set(sid, (remainingCreditByStudent.get(sid) || 0) + credit);
      debtByStudent.set(sid, (debtByStudent.get(sid) || 0) + debt);
      if (!teachersByStudent.has(sid)) teachersByStudent.set(sid, new Set());
      teachersByStudent.get(sid).add(tid);
    }

    for (const student of studentsRes.rows) {
      const sid = student.id;
      const teacherIds = teachersByStudent.get(sid) || new Set();
      for (const tid of teacherIds) {
        const key = walletKey(sid, tid);
        if (!remainingCreditByWallet.has(key)) {
          remainingCreditByWallet.set(key, creditByWallet.get(key) || 0);
        }
      }
      if (!remainingCreditByStudent.has(sid)) remainingCreditByStudent.set(sid, 0);
      if (!debtByStudent.has(sid)) debtByStudent.set(sid, 0);
    }

    // 2-й проход: legacy-неадресный пул ученика закрывает только оставшиеся долги
    // после адресных кошельков (переходный режим, чтобы старые платежи не "пропали").
    const lessonsByStudent = new Map();
    for (const l of lessonsRes.rows) {
      if (!lessonsByStudent.has(l.student_id)) lessonsByStudent.set(l.student_id, []);
      lessonsByStudent.get(l.student_id).push(l);
    }
    for (const [sid, lessons] of lessonsByStudent.entries()) {
      let unallocated = remainingUnallocatedCreditByStudent.get(sid) || 0;
      if (unallocated <= 0) continue;
      for (const lesson of lessons) {
        const cov = coverageByLessonId.get(lesson.id) || { paid: 0, unpaid: toNumber(lesson.price) };
        if (cov.unpaid <= 0) continue;
        const paidExtra = Math.max(0, Math.min(unallocated, cov.unpaid));
        if (paidExtra <= 0) continue;
        cov.paid += paidExtra;
        cov.unpaid = Math.max(0, cov.unpaid - paidExtra);
        coverageByLessonId.set(lesson.id, cov);
        unallocated -= paidExtra;
        if (unallocated <= 0) break;
      }
      remainingUnallocatedCreditByStudent.set(sid, unallocated);
    }

    // Пересчет student-агрегатов после обоих проходов FIFO.
    remainingCreditByStudent.clear();
    debtByStudent.clear();
    for (const student of studentsRes.rows) {
      const sid = student.id;
      const teacherIds = teachersByStudent.get(sid) || new Set();
      let rem = remainingUnallocatedCreditByStudent.get(sid) || 0;
      for (const tid of teacherIds) {
        rem += remainingCreditByWallet.get(walletKey(sid, tid)) || 0;
      }
      remainingCreditByStudent.set(sid, rem);

      let debt = 0;
      const lessons = lessonsByStudent.get(sid) || [];
      for (const lesson of lessons) {
        const cov = coverageByLessonId.get(lesson.id) || { paid: 0, unpaid: toNumber(lesson.price) };
        debt += cov.unpaid;
      }
      debtByStudent.set(sid, debt);
    }

    // Формируем плоский список уроков за период + агрегаты по преподавателям
    const lessonsInPeriod = [];
    const teacherAgg = new Map(); // teacherId -> {teacherId, teacherUsername, lessonsCount, amount, paid, unpaid}

    for (const l of lessonsRes.rows) {
      const d = toIsoDate(l.lesson_date);
      if (d < from || d > to) continue;
      if (bankTransferOnly && !studentIdsBankTransfer.has(l.student_id)) continue;
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
        status: (l.status || 'attended').toString(),
        isChargeable: l.is_chargeable === true,
        originLessonId: l.origin_lesson_id || null,
        originLessonDate: l.origin_lesson_date ? toIsoDate(l.origin_lesson_date) : null,
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
    let studentsFiltered = studentsRes.rows;
    if (bankTransferOnly) {
      studentsFiltered = studentsRes.rows.filter((s) => studentIdsBankTransfer.has(s.id));
    }
    const studentsOut = studentsFiltered.map((s) => ({
      id: s.id,
      name: s.name,
      parentName: s.parent_name || null,
      phone: s.phone || null,
      email: s.email || null,
      payByBankTransfer: s.pay_by_bank_transfer === true,
      teachers: studentTeachers.get(s.id) || [],
      depositsInPeriod: (studentTeachers.get(s.id) || []).reduce(
        (acc, t) => acc + (depositsInPeriodByWallet.get(walletKey(s.id, t.teacherId)) || 0),
        unallocatedDepositsInPeriodByStudent.get(s.id) || 0
      ),
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
        const sid = l.studentId;
        tNode.students.set(l.studentId, {
          studentId: sid,
          studentName: l.studentName,
          overallDebtAsOfTo: debtByStudent.get(sid) || 0,
          overallPrepaidAsOfTo: remainingCreditByStudent.get(sid) || 0,
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
        status: l.status,
        isChargeable: l.isChargeable,
        originLessonId: l.originLessonId,
        originLessonDate: l.originLessonDate || null,
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
      debug: {
        lessonsUpToTo: lessonsRes.rows.length,
        minLessonDate,
        maxLessonDate,
      },
      totals: {
        lessonsCount: lessonsInPeriod.length,
        lessonsAmount: lessonsInPeriod.reduce((acc, x) => acc + x.price, 0),
        paidAmount: lessonsInPeriod.reduce((acc, x) => acc + x.paidAmount, 0),
        unpaidAmount: lessonsInPeriod.reduce((acc, x) => acc + x.unpaidAmount, 0),
        missedCount: lessonsInPeriod.filter((x) => x.status === 'missed').length,
        makeupCount: lessonsInPeriod.filter((x) => x.status === 'makeup').length,
        cancelSameDayCount: lessonsInPeriod.filter((x) => x.status === 'cancel_same_day').length,
        cancelSameDayFreeCount: lessonsInPeriod.filter((x) => x.status === 'cancel_same_day' && !x.isChargeable).length,
        cancelSameDayPaidCount: lessonsInPeriod.filter((x) => x.status === 'cancel_same_day' && x.isChargeable).length,
        makeupPendingCount: Math.max(
          lessonsInPeriod.filter((x) => x.status === 'missed' || x.status === 'cancel_same_day').length -
            lessonsInPeriod.filter((x) => x.status === 'makeup').length,
          0
        ),
      },
      teachers: teacherOut,
      students: studentsOut,
      lessons: lessonsInPeriod,
      tree,
    };

    if (format === 'csv') {
      const header = [
        'дата',
        'время',
        'преподаватель',
        'ученик',
        'сумма',
        'статус',
      ];
      const rows = [header];
      for (const l of lessonsInPeriod) {
        rows.push([
          l.lessonDate,
          l.lessonTime || '',
          l.teacherUsername || '',
          l.studentName || '',
          l.price,
          l.isPaid ? 'оплачено' : 'долг',
        ]);
      }
      const csv = asCsv(rows);
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      const suffix = bankTransferOnly ? '_raschetnyi_schet' : '';
      res.setHeader('Content-Disposition', `attachment; filename="accounting_${from}_${to}${suffix}.csv"`);
      return res.status(200).send(csv);
    }

    return res.json(payload);
  } catch (error) {
    console.error('Ошибка выгрузки бухгалтерии:', error);
    return res.status(500).json({ message: 'Ошибка выгрузки бухгалтерии' });
  }
};

// GET /admin/accounting/transactions-export?from=YYYY-MM-DD&to=YYYY-MM-DD&format=json|csv
export const exportAccountingTransactions = async (req, res) => {
  try {
    const from = (req.query.from || '').toString();
    const to = (req.query.to || '').toString();
    const formatRaw = ((req.query.format || 'json').toString() || 'json').toLowerCase();
    const format = formatRaw === 'csv' ? 'csv' : 'json';
    const bankTransferOnly = req.query.bank_transfer_only === '1' || req.query.bank_transfer_only === 'true';

    if (!isValidISODate(from) || !isValidISODate(to)) {
      return res.status(400).json({ message: 'Параметры from/to обязательны в формате YYYY-MM-DD' });
    }
    if (to < from) {
      return res.status(400).json({ message: 'to должен быть >= from' });
    }

    const txRes = await pool.query(
      `SELECT t.id,
              t.student_id,
              COALESCE(s.name, '') as student_name,
              COALESCE(s.pay_by_bank_transfer, false) as pay_by_bank_transfer,
              t.type,
              t.amount,
              t.description,
              t.lesson_id,
              t.created_at,
              t.created_by,
              COALESCE(u.email, '') AS created_by_email,
              ${sqlUserAccountingNameOrEmpty('u')} AS created_by_display_name
       FROM transactions t
       LEFT JOIN students s ON s.id = t.student_id
       LEFT JOIN users u ON u.id = t.created_by
       WHERE t.created_at >= $1::date
         AND t.created_at < ($2::date + interval '1 day')
       ORDER BY t.created_at ASC, t.id ASC`,
      [from, to]
    );

    const rows = bankTransferOnly
      ? txRes.rows.filter((r) => r.pay_by_bank_transfer === true)
      : txRes.rows;

    if (format === 'csv') {
      const header = [
        'transaction_id',
        'student_id',
        'student_name',
        'type',
        'amount',
        'description',
        'lesson_id',
        'created_at',
        'created_by',
        'created_by_display_name',
        'created_by_email',
      ];
      const csvRows = [header];
      for (const r of rows) {
        csvRows.push([
          r.id,
          r.student_id,
          r.student_name,
          r.type,
          toNumber(r.amount),
          r.description || '',
          r.lesson_id || '',
          (r.created_at instanceof Date ? r.created_at.toISOString() : (r.created_at || '').toString()),
          r.created_by || '',
          r.created_by_display_name || r.created_by_email || '',
          r.created_by_email || '',
        ]);
      }
      const csv = asCsv(csvRows);
      const suffix = bankTransferOnly ? '_raschetnyi_schet' : '';
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', `attachment; filename="transactions_${from}_${to}${suffix}.csv"`);
      return res.status(200).send(csv);
    }

    return res.json({
      from,
      to,
      bankTransferOnly,
      count: rows.length,
      transactions: rows.map((r) => ({
        id: r.id,
        studentId: r.student_id,
        studentName: r.student_name,
        type: r.type,
        amount: toNumber(r.amount),
        description: r.description || null,
        lessonId: r.lesson_id || null,
        createdAt: r.created_at,
        createdBy: r.created_by || null,
        createdByDisplayName: r.created_by_display_name || r.created_by_email || null,
        createdByEmail: r.created_by_email || null,
      })),
    });
  } catch (error) {
    console.error('Ошибка выгрузки транзакций:', error);
    return res.status(500).json({ message: 'Ошибка выгрузки транзакций' });
  }
};

