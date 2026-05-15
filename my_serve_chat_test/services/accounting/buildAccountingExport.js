import { sqlUserAccountingName } from '../../utils/userAccountingDisplaySql.js';
import { closedOriginLessonIds } from '../../utils/makeupDebts.js';

const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export const isValidISODate = (s) => typeof s === 'string' && ISO_DATE_RE.test(s);

const toNumber = (v) => {
  if (v == null) return 0;
  const n = typeof v === 'number' ? v : parseFloat(v.toString());
  return Number.isFinite(n) ? n : 0;
};

const toIsoDate = (v) => {
  if (!v) return '';
  if (typeof v === 'string') return v.length >= 10 ? v.slice(0, 10) : v;
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  try {
    return new Date(v).toISOString().slice(0, 10);
  } catch (_) {
    return '';
  }
};

const walletKey = (studentId, teacherId) => `${studentId}:${teacherId}`;

/**
 * Собирает полный payload по бухгалтерии за период.
 * Не зависит от res/req; одинаковая логика для JSON, CSV и XLSX экспортов.
 *
 * @param {import('pg').Pool} pool
 * @param {Object} opts
 * @param {string} opts.from YYYY-MM-DD
 * @param {string} opts.to YYYY-MM-DD
 * @param {boolean} [opts.bankTransferOnly]
 */
export const buildAccountingExport = async (pool, { from, to, bankTransferOnly = false }) => {
  if (!isValidISODate(from) || !isValidISODate(to)) {
    throw Object.assign(new Error('Параметры from/to обязательны в формате YYYY-MM-DD'), {
      statusCode: 400,
    });
  }
  if (to < from) {
    throw Object.assign(new Error('to должен быть >= from'), { statusCode: 400 });
  }

  const teachersRes = await pool.query(
    `SELECT id, email, display_name,
            ${sqlUserAccountingName('u')} AS accounting_name
     FROM users u
     ORDER BY accounting_name`
  );
  const teacherById = new Map(teachersRes.rows.map((r) => [r.id, r.accounting_name || r.email || '']));

  const linksRes = await pool.query(
    `SELECT ts.teacher_id, ts.student_id, ${sqlUserAccountingName('u')} AS teacher_username
     FROM teacher_students ts
     JOIN users u ON u.id = ts.teacher_id`
  );
  const studentTeachers = new Map();
  for (const row of linksRes.rows) {
    const sid = row.student_id;
    if (!studentTeachers.has(sid)) studentTeachers.set(sid, []);
    studentTeachers.get(sid).push({ teacherId: row.teacher_id, teacherUsername: row.teacher_username });
  }

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
    if (r.teacher_id == null) unallocatedCreditByStudent.set(r.student_id, amount);
    else creditByWallet.set(walletKey(r.student_id, r.teacher_id), amount);
  }

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
    if (r.teacher_id == null) unallocatedDepositsInPeriodByStudent.set(r.student_id, amount);
    else depositsInPeriodByWallet.set(walletKey(r.student_id, r.teacher_id), amount);
  }

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

  const lessonsByWallet = new Map();
  for (const l of lessonsRes.rows) {
    const key = walletKey(l.student_id, l.teacher_id);
    if (!lessonsByWallet.has(key)) lessonsByWallet.set(key, []);
    lessonsByWallet.get(key).push(l);
  }

  let minLessonDate = null;
  let maxLessonDate = null;
  for (const l of lessonsRes.rows) {
    const d = toIsoDate(l.lesson_date);
    if (!d) continue;
    if (!minLessonDate || d < minLessonDate) minLessonDate = d;
    if (!maxLessonDate || d > maxLessonDate) maxLessonDate = d;
  }

  const coverageByLessonId = new Map();
  const remainingCreditByWallet = new Map();
  const remainingUnallocatedCreditByStudent = new Map(unallocatedCreditByStudent);
  const remainingCreditByStudent = new Map();
  const debtByStudent = new Map();
  const teachersByStudent = new Map();
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

  const lessonsInPeriod = [];
  const teacherAgg = new Map();
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
      payByBankTransfer: st?.pay_by_bank_transfer === true,
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
        studentIds: new Set(),
      });
    }
    const a = teacherAgg.get(key);
    a.lessonsCount += 1;
    a.amount += row.price;
    a.paidAmount += row.paidAmount;
    a.unpaidAmount += row.unpaidAmount;
    a.studentIds.add(l.student_id);
  }

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

  const teacherOut = [...teacherAgg.values()]
    .map((t) => ({
      teacherId: t.teacherId,
      teacherUsername: t.teacherUsername,
      lessonsCount: t.lessonsCount,
      amount: t.amount,
      paidAmount: t.paidAmount,
      unpaidAmount: t.unpaidAmount,
      studentsCount: t.studentIds.size,
    }))
    .sort((a, b) => (a.teacherUsername || '').localeCompare(b.teacherUsername || ''));

  const closedOrigins = closedOriginLessonIds(lessonsRes.rows);
  const totals = {
    lessonsCount: lessonsInPeriod.length,
    lessonsAmount: lessonsInPeriod.reduce((acc, x) => acc + x.price, 0),
    paidAmount: lessonsInPeriod.reduce((acc, x) => acc + x.paidAmount, 0),
    unpaidAmount: lessonsInPeriod.reduce((acc, x) => acc + x.unpaidAmount, 0),
    attendedCount: lessonsInPeriod.filter((x) => x.status === 'attended').length,
    missedCount: lessonsInPeriod.filter((x) => x.status === 'missed').length,
    makeupCount: lessonsInPeriod.filter((x) => x.status === 'makeup').length,
    cancelSameDayCount: lessonsInPeriod.filter((x) => x.status === 'cancel_same_day').length,
    cancelSameDayFreeCount: lessonsInPeriod.filter((x) => x.status === 'cancel_same_day' && !x.isChargeable).length,
    cancelSameDayPaidCount: lessonsInPeriod.filter((x) => x.status === 'cancel_same_day' && x.isChargeable).length,
    makeupPendingCount: lessonsInPeriod.filter(
      (x) =>
        (x.status === 'missed' || x.status === 'cancel_same_day') &&
        !closedOrigins.has(x.lessonId)
    ).length,
    depositsAmount: studentsOut.reduce((acc, s) => acc + (s.depositsInPeriod || 0), 0),
    prepaidAmount: studentsOut.reduce((acc, s) => acc + (s.prepaidAsOfTo || 0), 0),
    debtAmount: studentsOut.reduce((acc, s) => acc + (s.debtAsOfTo || 0), 0),
  };

  return {
    period: { from, to },
    bankTransferOnly,
    debug: {
      lessonsUpToTo: lessonsRes.rows.length,
      minLessonDate,
      maxLessonDate,
    },
    totals,
    teachers: teacherOut,
    students: studentsOut,
    lessons: lessonsInPeriod,
    teacherById: Object.fromEntries(teacherById),
  };
};

/**
 * Транзакции за период [from..to] включительно.
 */
export const queryAccountingTransactions = async (pool, { from, to, bankTransferOnly = false }) => {
  if (!isValidISODate(from) || !isValidISODate(to)) {
    throw Object.assign(new Error('Параметры from/to обязательны в формате YYYY-MM-DD'), {
      statusCode: 400,
    });
  }
  if (to < from) {
    throw Object.assign(new Error('to должен быть >= from'), { statusCode: 400 });
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
            ${sqlUserAccountingName('u')} AS created_by_display_name,
            t.target_teacher_id,
            ${sqlUserAccountingName('tu')} AS target_teacher_display_name
     FROM transactions t
     LEFT JOIN students s ON s.id = t.student_id
     LEFT JOIN users u ON u.id = t.created_by
     LEFT JOIN users tu ON tu.id = t.target_teacher_id
     WHERE t.created_at >= $1::date
       AND t.created_at < ($2::date + interval '1 day')
     ORDER BY t.created_at ASC, t.id ASC`,
    [from, to]
  );

  const rows = bankTransferOnly
    ? txRes.rows.filter((r) => r.pay_by_bank_transfer === true)
    : txRes.rows;

  return rows.map((r) => ({
    id: r.id,
    studentId: r.student_id,
    studentName: r.student_name,
    payByBankTransfer: r.pay_by_bank_transfer === true,
    type: r.type,
    amount: toNumber(r.amount),
    description: r.description || null,
    lessonId: r.lesson_id || null,
    createdAt: r.created_at,
    createdBy: r.created_by || null,
    createdByDisplayName: r.created_by_display_name || r.created_by_email || null,
    createdByEmail: r.created_by_email || null,
    targetTeacherId: r.target_teacher_id || null,
    targetTeacherDisplayName: r.target_teacher_display_name || null,
  }));
};
