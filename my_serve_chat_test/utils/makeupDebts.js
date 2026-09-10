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

export const MAKEUP_ORIGIN_UNIQUE_INDEX = 'ux_lessons_makeup_origin';

export const isMakeupOriginUniqueViolation = (error) =>
  error?.code === '23505' && String(error?.constraint || '') === MAKEUP_ORIGIN_UNIQUE_INDEX;

/** Сериализует отработки одного ученика у преподавателя до конца транзакции. */
export const lockMakeupForStudent = async (client, { teacherId, studentId }) => {
  await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [
    `lesson:makeup-student:${teacherId}:${studentId}`,
  ]);
};

const MAKEUP_ORIGIN_STATUSES = new Set(['missed', 'cancel_same_day']);

export const normalizeLessonTimeHHMM = (value) => {
  if (value == null || value === '') return '';
  if (value instanceof Date) {
    const hh = String(value.getHours()).padStart(2, '0');
    const mm = String(value.getMinutes()).padStart(2, '0');
    return `${hh}:${mm}`;
  }
  const s = String(value).trim();
  const matched = s.match(/(\d{1,2}):(\d{2})/);
  if (matched) return `${matched[1].padStart(2, '0')}:${matched[2]}`;
  return s.slice(0, 5);
};

const parsedLessonStatus = (item) =>
  typeof item?.status === 'string' ? item.status.trim() : 'attended';

/**
 * Пропуски, на которые уже ссылается отработка в другом отчёте, нельзя удалять
 * при пересборке: иначе ON DELETE SET NULL рвёт связь и пропуск можно списать снова.
 */
export const matchPreservedMakeupOrigins = ({ oldLessons, parsedLessons, referencedOriginIds }) => {
  const referenced = new Set(
    [...(referencedOriginIds || [])].map(Number).filter((id) => Number.isFinite(id))
  );
  const parsed = Array.isArray(parsedLessons) ? parsedLessons : [];
  const referencedOld = (oldLessons || []).filter((row) => referenced.has(Number(row.id)));
  const preservedByParsedIndex = new Map();
  const usedIdx = new Set();
  const preservedOldIds = new Set();

  const isCandidate = (index, oldRow, requireTime) => {
    if (usedIdx.has(index)) return false;
    const item = parsed[index];
    const status = parsedLessonStatus(item);
    if (!MAKEUP_ORIGIN_STATUSES.has(status)) return false;
    if (status !== String(oldRow.status || '')) return false;
    if (Number(item.studentId) !== Number(oldRow.student_id)) return false;
    if (!requireTime) return true;
    const oldTime = normalizeLessonTimeHHMM(oldRow.lesson_time);
    const newTime = normalizeLessonTimeHHMM(item.lessonTimeHHMM || item.timeStart);
    return oldTime === newTime;
  };

  for (const oldRow of referencedOld) {
    const idx = parsed.findIndex((_, i) => isCandidate(i, oldRow, true));
    if (idx < 0) continue;
    usedIdx.add(idx);
    preservedOldIds.add(Number(oldRow.id));
    preservedByParsedIndex.set(idx, oldRow);
  }

  const stillUnmatched = referencedOld.filter((row) => !preservedOldIds.has(Number(row.id)));
  for (const oldRow of stillUnmatched) {
    if (preservedOldIds.has(Number(oldRow.id))) continue;
    const remainingSame = stillUnmatched.filter(
      (row) =>
        !preservedOldIds.has(Number(row.id)) &&
        Number(row.student_id) === Number(oldRow.student_id) &&
        String(row.status || '') === String(oldRow.status || '')
    );
    const candidateIdx = [];
    parsed.forEach((_, i) => {
      if (isCandidate(i, oldRow, false)) candidateIdx.push(i);
    });
    if (remainingSame.length !== 1 || candidateIdx.length !== 1) continue;
    const idx = candidateIdx[0];
    usedIdx.add(idx);
    preservedOldIds.add(Number(oldRow.id));
    preservedByParsedIndex.set(idx, oldRow);
  }

  const unmatched = referencedOld.filter((row) => !preservedOldIds.has(Number(row.id)));
  return { preservedByParsedIndex, unmatched };
};
