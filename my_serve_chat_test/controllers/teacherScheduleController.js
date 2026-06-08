import pool from '../db.js';
import { parsePositiveInt } from '../utils/sanitize.js';
import { sqlUserAccountingName, sqlUserAccountingNameOrEmpty } from '../utils/userAccountingDisplaySql.js';
import { computeTeacherWorkProfile } from '../services/accounting/teacherWorkProfile.js';

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

const percentile = (arr, p) => {
  if (!arr || arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.floor(p * sorted.length)));
  return sorted[idx];
};

const parseTeacherIds = (raw) => {
  const ids = (raw || '')
    .toString()
    .split(',')
    .map((part) => parsePositiveInt(part.trim()))
    .filter((id) => id > 0);
  return [...new Set(ids)];
};

const loadLevelForCount = (count, thresholdHigh, thresholdOverload) => {
  if (count <= 0) return 'empty';
  if (count >= thresholdOverload) return 'overload';
  if (count >= thresholdHigh) return 'high';
  return 'normal';
};

/**
 * GET /admin/accounting/teacher-schedule/overview?from=&to=&teacher_ids=1,2,3
 * Сводная теплокарта до 5 преподавателей + ученики по слотам (только суперпользователь).
 */
export const getTeacherScheduleOverview = async (req, res) => {
  try {
    const period = parsePeriod(req.query);
    if (!period.ok) {
      return res.status(period.status).json({ message: period.message });
    }

    const teacherIds = parseTeacherIds(req.query?.teacher_ids);
    if (teacherIds.length === 0) {
      return res.status(400).json({ message: 'Укажите teacher_ids (1–5 через запятую)' });
    }
    if (teacherIds.length > 5) {
      return res.status(400).json({ message: 'Не более 5 преподавателей за раз' });
    }

    const teachersRes = await pool.query(
      `SELECT u.id,
              ${sqlUserAccountingNameOrEmpty('u')} AS label
       FROM users u
       WHERE u.id = ANY($1::int[])
       ORDER BY label ASC`,
      [teacherIds]
    );
    if (teachersRes.rows.length === 0) {
      return res.status(404).json({ message: 'Преподаватели не найдены' });
    }

    const lessonsRes = await pool.query(
      `SELECT l.created_by AS teacher_id,
              ${sqlUserAccountingNameOrEmpty('u')} AS teacher_label,
              EXTRACT(ISODOW FROM l.lesson_date)::int AS weekday,
              to_char(l.lesson_time, 'HH24:MI') AS time_slot,
              s.id AS student_id,
              COALESCE(s.name, '') AS student_name,
              COUNT(*)::int AS lesson_count
       FROM lessons l
       JOIN users u ON u.id = l.created_by
       JOIN students s ON s.id = l.student_id
       WHERE l.lesson_date >= $1::date
         AND l.lesson_date <= $2::date
         AND l.lesson_time IS NOT NULL
         AND l.created_by = ANY($3::int[])
       GROUP BY l.created_by, teacher_label, weekday, time_slot, s.id, s.name
       ORDER BY weekday, time_slot, teacher_label, student_name`,
      [period.from, period.to, teacherIds]
    );

    const teacherMeta = teachersRes.rows.map((r) => ({
      id: r.id,
      label: r.label || '',
    }));

    const countsByTeacher = new Map();
    for (const tid of teacherIds) countsByTeacher.set(tid, []);

    const cellMap = new Map();
    const activeWeekdays = new Set();
    const timeSet = new Set();

    for (const row of lessonsRes.rows) {
      const weekday = Number(row.weekday);
      const timeSlot = row.time_slot;
      const teacherId = Number(row.teacher_id);
      const lessonCount = Number(row.lesson_count) || 0;
      if (!timeSlot || weekday < 1 || weekday > 7 || lessonCount <= 0) continue;

      activeWeekdays.add(weekday);
      timeSet.add(timeSlot);

      const cellKey = `${weekday}:${timeSlot}`;
      if (!cellMap.has(cellKey)) {
        cellMap.set(cellKey, {
          weekday,
          time_slot: timeSlot,
          total_count: 0,
          by_teacher: new Map(),
        });
      }
      const cell = cellMap.get(cellKey);
      cell.total_count += lessonCount;

      if (!cell.by_teacher.has(teacherId)) {
        cell.by_teacher.set(teacherId, {
          teacher_id: teacherId,
          teacher_label: row.teacher_label || '',
          count: 0,
          students: [],
        });
      }
      const tCell = cell.by_teacher.get(teacherId);
      tCell.count += lessonCount;
      tCell.students.push({
        student_id: row.student_id,
        student_name: row.student_name || '',
        lesson_count: lessonCount,
      });
      countsByTeacher.get(teacherId)?.push(lessonCount);
    }

    const thresholdsByTeacher = new Map();
    for (const [tid, counts] of countsByTeacher.entries()) {
      const p75 = percentile(counts, 0.75);
      thresholdsByTeacher.set(tid, {
        high: Math.max(2, p75),
        overload: Math.max(3, Math.ceil(p75 * 1.25)),
      });
    }

    const cellsOut = [];
    let overloadCells = 0;
    let gapCells = 0;
    let maxTotal = 0;

    for (const timeSlot of [...timeSet].sort((a, b) => a.localeCompare(b))) {
      for (let weekday = 1; weekday <= 7; weekday += 1) {
        const cellKey = `${weekday}:${timeSlot}`;
        const existing = cellMap.get(cellKey);
        const totalCount = existing?.total_count || 0;
        maxTotal = Math.max(maxTotal, totalCount);

        const isGap = activeWeekdays.has(weekday) && totalCount === 0;
        if (isGap) gapCells += 1;

        const teachersInCell = [];
        let cellOverload = false;

        for (const meta of teacherMeta) {
          const tid = meta.id;
          const tData = existing?.by_teacher.get(tid);
          const count = tData?.count || 0;
          const thr = thresholdsByTeacher.get(tid) || { high: 2, overload: 3 };
          const loadLevel = loadLevelForCount(count, thr.high, thr.overload);
          if (loadLevel === 'overload') cellOverload = true;
          teachersInCell.push({
            teacher_id: tid,
            teacher_label: tData?.teacher_label || meta.label,
            count,
            load_level: loadLevel,
            students: tData?.students || [],
          });
        }

        if (cellOverload) overloadCells += 1;

        if (totalCount > 0 || isGap) {
          cellsOut.push({
            weekday,
            time_slot: timeSlot,
            total_count: totalCount,
            is_gap: isGap,
            is_overload: cellOverload,
            teachers: teachersInCell,
          });
        }
      }
    }

    return res.json({
      from: period.from,
      to: period.to,
      teachers: teacherMeta,
      time_slots: [...timeSet].sort((a, b) => a.localeCompare(b)),
      cells: cellsOut,
      max_total_count: maxTotal,
      active_weekdays: [...activeWeekdays].sort((a, b) => a - b),
      insights: {
        overload_cells: overloadCells,
        gap_cells: gapCells,
        total_lessons: cellsOut.reduce((acc, c) => acc + c.total_count, 0),
      },
    });
  } catch (error) {
    console.error('getTeacherScheduleOverview:', error);
    return res.status(500).json({ message: 'Ошибка сводного графика' });
  }
};

const WEEKDAY_LABELS = ['', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/** ISODOW (1=Пн … 7=Вс) → PostgreSQL DOW (0=Вс, 1=Пн …) для work profile */
const isodowToPgDow = (isodow) => (isodow === 7 ? 0 : isodow);

const placementStatus = (studentsCount, weeksActive, high, overload) => {
  if (weeksActive < 2) return 'unstable';
  if (studentsCount >= overload) return 'full';
  if (studentsCount >= high) return 'limited';
  return 'open';
};

const placementLabel = (status) => {
  switch (status) {
    case 'open':
      return 'Можно поставить';
    case 'limited':
      return 'На пределе';
    case 'full':
      return 'Заполнено';
    case 'unstable':
      return 'Редкий слот';
    default:
      return status;
  }
};

/**
 * GET /admin/accounting/teacher-schedule/placement?from=&to=&teacher_ids=1,2,3
 * По каждому преподавателю: устойчивые дни/время, куда можно поставить ребёнка.
 */
export const getTeacherPlacementPlan = async (req, res) => {
  try {
    const period = parsePeriod(req.query);
    if (!period.ok) {
      return res.status(period.status).json({ message: period.message });
    }

    const teacherIds = parseTeacherIds(req.query?.teacher_ids);
    if (teacherIds.length === 0) {
      return res.status(400).json({ message: 'Укажите teacher_ids (1–5 через запятую)' });
    }
    if (teacherIds.length > 5) {
      return res.status(400).json({ message: 'Не более 5 преподавателей за раз' });
    }

    const teachersRes = await pool.query(
      `SELECT u.id,
              ${sqlUserAccountingNameOrEmpty('u')} AS label
       FROM users u
       WHERE u.id = ANY($1::int[])
       ORDER BY label ASC`,
      [teacherIds]
    );
    if (teachersRes.rows.length === 0) {
      return res.status(404).json({ message: 'Преподаватели не найдены' });
    }

    const slotsRes = await pool.query(
      `SELECT l.created_by AS teacher_id,
              EXTRACT(ISODOW FROM l.lesson_date)::int AS weekday,
              to_char(l.lesson_time, 'HH24:MI') AS time_slot,
              COUNT(*)::int AS lessons_count,
              COUNT(DISTINCT l.student_id)::int AS students_count,
              COUNT(DISTINCT date_trunc('week', l.lesson_date))::int AS weeks_active,
              COALESCE(
                json_agg(
                  DISTINCT jsonb_build_object(
                    'student_id', s.id,
                    'student_name', COALESCE(s.name, '')
                  )
                ) FILTER (WHERE s.id IS NOT NULL),
                '[]'::json
              ) AS students
       FROM lessons l
       JOIN students s ON s.id = l.student_id
       WHERE l.lesson_date >= $1::date
         AND l.lesson_date <= $2::date
         AND l.lesson_time IS NOT NULL
         AND l.created_by = ANY($3::int[])
       GROUP BY l.created_by, weekday, time_slot
       ORDER BY l.created_by, weekday, time_slot`,
      [period.from, period.to, teacherIds]
    );

    const slotsByTeacher = new Map();
    for (const tid of teacherIds) slotsByTeacher.set(tid, []);

    for (const row of slotsRes.rows) {
      const tid = Number(row.teacher_id);
      const weekday = Number(row.weekday);
      const timeSlot = row.time_slot;
      if (!timeSlot || weekday < 1 || weekday > 7) continue;
      slotsByTeacher.get(tid)?.push({
        weekday,
        time_slot: timeSlot,
        lessons_count: Number(row.lessons_count) || 0,
        students_count: Number(row.students_count) || 0,
        weeks_active: Number(row.weeks_active) || 0,
        students: Array.isArray(row.students) ? row.students : [],
      });
    }

    const teachersOut = [];
    for (const meta of teachersRes.rows) {
      const tid = meta.id;
      const rawSlots = slotsByTeacher.get(tid) || [];
      const studentCounts = rawSlots.map((s) => s.students_count);
      const p75 = percentile(studentCounts, 0.75);
      const high = Math.max(2, p75);
      const overload = Math.max(3, Math.ceil(p75 * 1.25));

      let profile = null;
      try {
        profile = await computeTeacherWorkProfile(pool, tid, {
          anchorDate: period.to,
          lookbackDays: 84,
        });
      } catch (_) {
        profile = null;
      }
      const typicalDows = new Set(profile?.typicalDows || []);

      const placementSlots = rawSlots
        .map((slot) => {
          const pgDow = isodowToPgDow(slot.weekday);
          const isTypicalDow = typicalDows.has(pgDow);
          const status = placementStatus(
            slot.students_count,
            slot.weeks_active,
            high,
            overload
          );
          return {
            weekday: slot.weekday,
            weekday_label: WEEKDAY_LABELS[slot.weekday] || '',
            time_slot: slot.time_slot,
            lessons_count: slot.lessons_count,
            students_count: slot.students_count,
            weeks_active: slot.weeks_active,
            is_typical_day: isTypicalDow,
            is_recurring: slot.weeks_active >= 2,
            placement_status: status,
            placement_label: placementLabel(status),
            students: slot.students,
          };
        })
        .sort((a, b) => {
          const statusOrder = { open: 0, limited: 1, unstable: 2, full: 3 };
          const sa = statusOrder[a.placement_status] ?? 9;
          const sb = statusOrder[b.placement_status] ?? 9;
          if (sa !== sb) return sa - sb;
          if (a.weekday !== b.weekday) return a.weekday - b.weekday;
          return a.time_slot.localeCompare(b.time_slot);
        });

      const openSlots = placementSlots.filter((s) => s.placement_status === 'open').length;

      teachersOut.push({
        teacher_id: tid,
        teacher_label: meta.label || '',
        typical_weekdays: [...typicalDows]
          .sort((a, b) => a - b)
          .map((d) => (d === 0 ? 'Вс' : WEEKDAY_LABELS[d] || ''))
          .filter(Boolean),
        open_slots_count: openSlots,
        slots: placementSlots,
      });
    }

    return res.json({
      from: period.from,
      to: period.to,
      teachers: teachersOut,
      hint: 'Слоты по фактическим урокам за период. «Можно поставить» — устойчивый слот с запасом по загрузке.',
    });
  } catch (error) {
    console.error('getTeacherPlacementPlan:', error);
    return res.status(500).json({ message: 'Ошибка планировщика' });
  }
};
