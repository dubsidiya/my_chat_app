import pool from '../db.js';
import { parsePositiveInt } from '../utils/sanitize.js';
import { sqlUserAccountingName, sqlUserAccountingNameOrEmpty } from '../utils/userAccountingDisplaySql.js';

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

/** GET /admin/accounting/teacher-schedule/teachers?from=&to= */
export const getTeacherScheduleTeachers = async (req, res) => {
  try {
    const period = parsePeriod(req.query);
    if (!period.ok) {
      return res.status(period.status).json({ message: period.message });
    }
    const result = await pool.query(
      `SELECT DISTINCT u.id,
              ${sqlUserAccountingName('u')} AS label
       FROM lessons l
       JOIN users u ON u.id = l.created_by
       WHERE l.lesson_date >= $1::date AND l.lesson_date <= $2::date
       ORDER BY label ASC`,
      [period.from, period.to]
    );
    return res.json({
      from: period.from,
      to: period.to,
      teachers: result.rows.map((r) => ({
        id: r.id,
        label: r.label || '',
      })),
    });
  } catch (error) {
    console.error('getTeacherScheduleTeachers:', error);
    return res.status(500).json({ message: 'Ошибка списка преподавателей' });
  }
};

/** GET /admin/accounting/teacher-schedule?from=&to=&teacher_id= */
export const getTeacherScheduleHeatmap = async (req, res) => {
  try {
    const period = parsePeriod(req.query);
    if (!period.ok) {
      return res.status(period.status).json({ message: period.message });
    }
    const teacherId = parsePositiveInt(req.query?.teacher_id);
    if (!teacherId) {
      return res.status(400).json({ message: 'Укажите teacher_id' });
    }

    const userRow = await pool.query(
      `SELECT id, ${sqlUserAccountingNameOrEmpty('u')} AS label
       FROM users u WHERE u.id = $1`,
      [teacherId]
    );
    if (userRow.rows.length === 0) {
      return res.status(404).json({ message: 'Преподаватель не найден' });
    }

    const cellsRes = await pool.query(
      `SELECT EXTRACT(ISODOW FROM lesson_date)::int AS weekday,
              to_char(lesson_time, 'HH24:MI') AS time_slot,
              COUNT(*)::int AS count
       FROM lessons
       WHERE created_by = $1
         AND lesson_date >= $2::date
         AND lesson_date <= $3::date
         AND lesson_time IS NOT NULL
       GROUP BY weekday, time_slot
       ORDER BY weekday, time_slot`,
      [teacherId, period.from, period.to]
    );

    const noTimeRes = await pool.query(
      `SELECT COUNT(*)::int AS count
       FROM lessons
       WHERE created_by = $1
         AND lesson_date >= $2::date
         AND lesson_date <= $3::date
         AND lesson_time IS NULL`,
      [teacherId, period.from, period.to]
    );

    const timeSet = new Set();
    const cells = [];
    let maxCount = 0;
    let totalWithTime = 0;
    for (const row of cellsRes.rows) {
      const weekday = Number(row.weekday);
      const timeSlot = row.time_slot;
      const count = Number(row.count) || 0;
      if (!timeSlot || weekday < 1 || weekday > 7) continue;
      timeSet.add(timeSlot);
      totalWithTime += count;
      maxCount = Math.max(maxCount, count);
      cells.push({ weekday, time_slot: timeSlot, count });
    }

    const timeSlots = [...timeSet].sort((a, b) => a.localeCompare(b));
    const noTimeCount = Number(noTimeRes.rows[0]?.count) || 0;

    return res.json({
      teacher_id: teacherId,
      teacher_label: userRow.rows[0].label || '',
      from: period.from,
      to: period.to,
      time_slots: timeSlots,
      cells,
      max_count: maxCount,
      total_lessons: totalWithTime + noTimeCount,
      lessons_without_time: noTimeCount,
    });
  } catch (error) {
    console.error('getTeacherScheduleHeatmap:', error);
    return res.status(500).json({ message: 'Ошибка графика работы' });
  }
};
