import pool from '../db.js';
import { parsePositiveInt } from '../utils/sanitize.js';
import { buildAccountingExport } from '../services/accounting/buildAccountingExport.js';
import { closedOriginLessonIds } from '../utils/makeupDebts.js';

const isValidISODate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);

function parsePeriod(query) {
  const from = query?.from;
  const to = query?.to;
  if (!isValidISODate(from) || !isValidISODate(to)) {
    return { ok: false, status: 400, message: 'Укажите from и to в формате YYYY-MM-DD' };
  }
  if (from > to) {
    return { ok: false, status: 400, message: 'from не может быть позже to' };
  }
  return { ok: true, from, to };
}

function buildStudentsForTeacher(payload, teacherId) {
  const closed = closedOriginLessonIds(
    (payload.lessons || []).map((l) => ({
      id: l.lessonId,
      status: l.status,
      origin_lesson_id: l.originLessonId,
    }))
  );

  const byStudent = new Map();

  const ensure = (studentId, studentName, debtAsOfTo) => {
    if (!byStudent.has(studentId)) {
      byStudent.set(studentId, {
        studentId,
        studentName: studentName || '',
        debtAsOfTo: debtAsOfTo || 0,
        unpaidInPeriod: 0,
        openMakeupCount: 0,
        lessonsInPeriod: 0,
      });
    }
    return byStudent.get(studentId);
  };

  for (const s of payload.students || []) {
    const teachers = s.teachers || [];
    const linked = teachers.some((t) => Number(t.teacherId) === teacherId);
    if (!linked) continue;
    ensure(s.id, s.name, s.debtAsOfTo);
  }

  for (const l of payload.lessons || []) {
    if (Number(l.teacherId) !== teacherId) continue;
    const row = ensure(l.studentId, l.studentName, null);
    row.lessonsInPeriod += 1;
    row.unpaidInPeriod += Number(l.unpaidAmount || 0);
    const status = (l.status || '').toString();
    if (
      (status === 'missed' || status === 'cancel_same_day') &&
      !closed.has(Number(l.lessonId))
    ) {
      row.openMakeupCount += 1;
    }
    const st = (payload.students || []).find((x) => Number(x.id) === Number(l.studentId));
    if (st && row.debtAsOfTo === 0) {
      row.debtAsOfTo = Number(st.debtAsOfTo || 0);
    }
  }

  return [...byStudent.values()]
    .map((row) => ({
      ...row,
      unpaidInPeriod: Math.round(row.unpaidInPeriod * 100) / 100,
      debtAsOfTo: Math.round(row.debtAsOfTo * 100) / 100,
    }))
    .sort((a, b) => {
      const debtDiff = (b.debtAsOfTo || 0) - (a.debtAsOfTo || 0);
      if (debtDiff !== 0) return debtDiff;
      return (a.studentName || '').localeCompare(b.studentName || '', 'ru');
    });
}

/** GET /admin/accounting/nagavisor?teacher_id=&from=&to= — сводка nagavisor1.0 */
export const getNagavisor = async (req, res) => {
  try {
    const teacherId = parsePositiveInt(req.query.teacher_id);
    if (!teacherId) {
      return res.status(400).json({ message: 'Укажите teacher_id' });
    }
    const period = parsePeriod(req.query);
    if (!period.ok) {
      return res.status(period.status).json({ message: period.message });
    }

    const payload = await buildAccountingExport(pool, {
      from: period.from,
      to: period.to,
      bankTransferOnly: false,
    });

    const stats =
      (payload.teacherStats || []).find((s) => Number(s.teacherId) === teacherId) || null;
    const salary =
      (payload.salaries || []).find((s) => Number(s.teacherId) === teacherId) || null;
    const teacherRow =
      (payload.teachers || []).find((t) => Number(t.teacherId) === teacherId) || null;

    const label =
      stats?.teacherUsername ||
      salary?.teacherUsername ||
      teacherRow?.teacherUsername ||
      '';

    return res.json({
      period: payload.period,
      teacherId,
      teacherLabel: label,
      stats,
      salary,
      students: buildStudentsForTeacher(payload, teacherId),
    });
  } catch (error) {
    console.error('Ошибка nagavisor:', error);
    const status = error.statusCode && Number.isInteger(error.statusCode) ? error.statusCode : 500;
    return res.status(status).json({ message: error.message || 'Ошибка загрузки карточки преподавателя' });
  }
};
