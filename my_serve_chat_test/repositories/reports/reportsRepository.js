export const findAllReportsByUser = async (db, userId) => {
  return db.query(
    `SELECT r.*, COUNT(rl.lesson_id) as lessons_count
     FROM reports r
     LEFT JOIN report_lessons rl ON r.id = rl.report_id
     WHERE r.created_by = $1
     GROUP BY r.id
     ORDER BY r.report_date DESC, r.created_at DESC`,
    [userId]
  );
};

export const findReportsList = async (db, { dateFrom, dateTo, isLate }) => {
  const conditions = [];
  const params = [];
  let idx = 1;

  if (dateFrom && /^\d{4}-\d{2}-\d{2}$/.test(dateFrom)) {
    conditions.push(`r.report_date >= $${idx}::date`);
    params.push(dateFrom);
    idx++;
  }
  if (dateTo && /^\d{4}-\d{2}-\d{2}$/.test(dateTo)) {
    conditions.push(`r.report_date <= $${idx}::date`);
    params.push(dateTo);
    idx++;
  }
  if (isLate === 'true') {
    conditions.push('r.is_late = true');
  } else if (isLate === 'false') {
    conditions.push('r.is_late = false');
  }

  const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
  return db.query(
    `SELECT r.*, u.email AS created_by_email,
            COUNT(rl.lesson_id)::int AS lessons_count
     FROM reports r
     LEFT JOIN users u ON r.created_by = u.id
     LEFT JOIN report_lessons rl ON r.id = rl.report_id
     ${whereClause}
     GROUP BY r.id, u.email
     ORDER BY r.report_date DESC, r.created_at DESC`,
    params
  );
};

export const findMonthlyTotals = async (db, { userId, firstDay, lastDayStr }) => {
  return db.query(
    `WITH month_lessons AS (
       SELECT l.id, l.lesson_date, l.price, r.id AS report_id, r.is_late
       FROM lessons l
       LEFT JOIN report_lessons rl ON rl.lesson_id = l.id
       LEFT JOIN reports r ON r.id = rl.report_id AND r.created_by = l.created_by
       WHERE l.created_by = $1
         AND l.lesson_date >= $2::date AND l.lesson_date <= $3::date
         AND COALESCE(l.is_chargeable, true) = true
     )
     SELECT
       COALESCE(SUM(price), 0) AS total_all,
       COALESCE(SUM(CASE WHEN is_late = true THEN price ELSE 0 END), 0) AS late_amount,
       COALESCE(SUM(CASE WHEN is_late IS DISTINCT FROM true THEN price ELSE 0 END), 0) AS income_counted
     FROM month_lessons`,
    [userId, firstDay, lastDayStr]
  );
};

export const findMonthlyBreakdown = async (db, { userId, firstDay, lastDayStr }) => {
  return db.query(
    `SELECT r.id AS report_id, r.report_date, r.is_late,
            COALESCE(SUM(CASE WHEN COALESCE(l.is_chargeable, true) = true THEN l.price ELSE 0 END), 0) AS amount
     FROM reports r
     LEFT JOIN report_lessons rl ON rl.report_id = r.id
     LEFT JOIN lessons l ON l.id = rl.lesson_id
     WHERE r.created_by = $1
       AND r.report_date >= $2::date AND r.report_date <= $3::date
     GROUP BY r.id, r.report_date, r.is_late
     ORDER BY r.report_date ASC`,
    [userId, firstDay, lastDayStr]
  );
};

export const findMonthlyNoReportAmount = async (db, { userId, firstDay, lastDayStr }) => {
  return db.query(
    `SELECT COALESCE(SUM(l.price), 0) AS amount
     FROM lessons l
     WHERE l.created_by = $1
       AND l.lesson_date >= $2::date AND l.lesson_date <= $3::date
       AND COALESCE(l.is_chargeable, true) = true
       AND NOT EXISTS (SELECT 1 FROM report_lessons rl WHERE rl.lesson_id = l.id)`,
    [userId, firstDay, lastDayStr]
  );
};

/** Сколько занятий в месяце на каждом ценнике (как в расчёте выручки за месяц). */
export const findMonthlyLessonCountsByPrice = async (db, { userId, firstDay, lastDayStr }) => {
  return db.query(
    `SELECT l.price::float8 AS price, COUNT(*)::int AS lessons_count
     FROM lessons l
     WHERE l.created_by = $1
       AND l.lesson_date >= $2::date AND l.lesson_date <= $3::date
       AND COALESCE(l.is_chargeable, true) = true
     GROUP BY l.price
     ORDER BY l.price ASC`,
    [userId, firstDay, lastDayStr]
  );
};

export const findReportByIdForViewer = async (db, { reportId, userId, isSuper }) => {
  return db.query(
    isSuper
      ? 'SELECT * FROM reports WHERE id = $1'
      : 'SELECT * FROM reports WHERE id = $1 AND created_by = $2',
    isSuper ? [reportId] : [reportId, userId]
  );
};

export const findReportLessons = async (db, reportId) => {
  return db.query(
    `SELECT l.*, s.name as student_name
     FROM report_lessons rl
     JOIN lessons l ON rl.lesson_id = l.id
     JOIN students s ON l.student_id = s.id
     WHERE rl.report_id = $1
     ORDER BY l.lesson_date, l.lesson_time`,
    [reportId]
  );
};

export const findUserEmailById = async (db, userId) => {
  return db.query('SELECT email FROM users WHERE id = $1', [userId]);
};

export const markReportAsNotLate = async (db, reportId) => {
  return db.query(
    `UPDATE reports SET is_late = false WHERE id = $1 RETURNING *`,
    [reportId]
  );
};
