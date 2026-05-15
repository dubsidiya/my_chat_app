/**
 * Открытый долг отработки: missed или cancel_same_day (в т.ч. платная отмена),
 * пока нет makeup с origin_lesson_id на этот урок.
 */
export const SQL_OPEN_MAKEUP_DEBT_ON_LESSON = `
  l.status IN ('missed', 'cancel_same_day')
  AND NOT EXISTS (
    SELECT 1
    FROM lessons m
    WHERE m.created_by = l.created_by
      AND m.student_id = l.student_id
      AND m.status = 'makeup'
      AND m.origin_lesson_id = l.id
  )
`;

/**
 * @param {Array<{ id: number, status?: string, origin_lesson_id?: number | null }>} lessons
 * @returns {Set<number>} lesson ids, закрытые отработкой
 */
export const closedOriginLessonIds = (lessons) => {
  const closed = new Set();
  for (const row of lessons) {
    if (row?.status === 'makeup' && row.origin_lesson_id != null) {
      closed.add(Number(row.origin_lesson_id));
    }
  }
  return closed;
};

/**
 * @param {Array<{ id: number, status?: string, origin_lesson_id?: number | null }>} lessons
 * @returns {number}
 */
export const countOpenMakeupDebts = (lessons) => {
  const closed = closedOriginLessonIds(lessons);
  let n = 0;
  for (const row of lessons) {
    const id = Number(row?.id);
    if (!Number.isFinite(id)) continue;
    const status = (row?.status || '').toString();
    if ((status === 'missed' || status === 'cancel_same_day') && !closed.has(id)) {
      n += 1;
    }
  }
  return n;
};
