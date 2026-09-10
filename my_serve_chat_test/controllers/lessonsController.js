import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';
import { parsePositiveInt, sanitizeMessageContent } from '../utils/sanitize.js';
import { sqlUserAccountingNameOrEmpty } from '../utils/userAccountingDisplaySql.js';
import { getUserTimeZone, getDateInTimeZoneISO } from '../utils/timezone.js';
import {
  beginIdempotent,
  completeIdempotent,
  getIdempotencyKey,
  hashIdempotencyPayload,
} from '../utils/idempotency.js';
import { logAccountingEvent } from '../utils/accountingAudit.js';
import {
  deleteLessonIncomeForLesson,
  syncNoReportLessonIncome,
} from '../services/accounting/teacherBalanceService.js';
import { isMakeupOriginUniqueViolation, lockMakeupForStudent } from '../utils/makeupDebts.js';
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const LESSON_STATUSES = new Set(['attended', 'missed', 'makeup', 'cancel_same_day']);
const LESSON_TIME_RE = /^\d{2}:\d{2}(:\d{2})?$/;

const round2 = (n) => Math.round(n * 100) / 100;
// Верхняя бизнес-граница цены занятия (M13): отсекает ошибочный ввод и переполнение DECIMAL(10,2).
const MAX_MONEY_AMOUNT = 1_000_000;
// Ограничение длины заметок занятия (M14).
const NOTES_MAX_LENGTH = 2000;
// Максимальный диапазон календарной сводки (M16).
const MAX_CALENDAR_SPAN_DAYS = 366;
// Максимум строк на страницу для списков (M17).
const LIST_MAX_LIMIT = 1000;

// M16: строгая проверка календарной даты — формат + round-trip через Date (UTC),
// чтобы несуществующие даты (например 2026-02-31) отклонялись как 400, а не падали в SQL.
const isRealCalendarDate = (value) => {
  if (typeof value !== 'string' || !ISO_DATE_RE.test(value)) return false;
  const ms = Date.parse(`${value}T00:00:00Z`);
  if (Number.isNaN(ms)) return false;
  return new Date(ms).toISOString().slice(0, 10) === value;
};

// M14: lesson_time — требуемый формат HH:MM[:SS] плюс реальные границы времени
// (иначе TIME-колонка на «25:99» даёт 500 вместо 400).
const isValidLessonTime = (value) => {
  if (typeof value !== 'string' || !LESSON_TIME_RE.test(value)) return false;
  const [h, m, s = '0'] = value.split(':');
  return Number(h) <= 23 && Number(m) <= 59 && Number(s) <= 59;
};

// M17: разбор необязательных limit/offset. При отсутствии параметров возвращаем
// { limit: null, offset: null } — поведение прежнее (все строки), клиент не ломается.
const parseLimitOffset = (req, maxLimit = LIST_MAX_LIMIT) => {
  const out = { limit: null, offset: null };
  const rawLimit = req.query?.limit;
  const rawOffset = req.query?.offset;
  if (rawLimit != null && String(rawLimit).trim() !== '') {
    const n = parseInt(String(rawLimit), 10);
    if (!Number.isInteger(n) || n < 1 || n > maxLimit) {
      return { error: `limit должен быть целым числом от 1 до ${maxLimit}` };
    }
    out.limit = n;
  }
  if (rawOffset != null && String(rawOffset).trim() !== '') {
    const n = parseInt(String(rawOffset), 10);
    if (!Number.isInteger(n) || n < 0) {
      return { error: 'offset должен быть неотрицательным целым числом' };
    }
    out.offset = n;
  }
  return out;
};

// Дописывает LIMIT/OFFSET к запросу и параметрам только при наличии значений.
const buildLimitOffsetSql = (params, { limit, offset }) => {
  let sql = '';
  if (limit != null) {
    params.push(limit);
    sql += ` LIMIT $${params.length}`;
  }
  if (offset != null) {
    params.push(offset);
    sql += ` OFFSET $${params.length}`;
  }
  return sql;
};

const hasStudentAccess = async (client, teacherId, studentId) => {
  const r = await client.query(
    'SELECT 1 FROM teacher_students WHERE teacher_id = $1 AND student_id = $2 LIMIT 1',
    [teacherId, studentId]
  );
  return r.rows.length > 0;
};

const resolveMakeupOrigin = async (client, { studentId, teacherId, originLessonId }) => {
  if (originLessonId) {
    const originResult = await client.query(
      `SELECT id, student_id, status, created_by, lesson_date
       FROM lessons
       WHERE id = $1
       LIMIT 1`,
      [originLessonId]
    );
    if (originResult.rows.length === 0) {
      return { errorStatus: 400, errorMessage: 'Исходный пропуск для отработки не найден' };
    }
    const origin = originResult.rows[0];
    if (origin.student_id !== studentId) {
      return { errorStatus: 400, errorMessage: 'Отработка должна ссылаться на занятие этого же ребенка' };
    }
    if (String(origin.created_by) !== String(teacherId)) {
      return { errorStatus: 403, errorMessage: 'Нельзя ссылаться на занятие другого преподавателя' };
    }
    if (!['missed', 'cancel_same_day'].includes(origin.status)) {
      return { errorStatus: 400, errorMessage: 'Отрабатывать можно только пропуск или отмену в день' };
    }
    await lockMakeupForStudent(client, { teacherId, studentId });
    const alreadyMakeup = await client.query(
      `SELECT id
       FROM lessons
       WHERE created_by = $1
         AND student_id = $2
         AND status = 'makeup'
         AND origin_lesson_id = $3
       LIMIT 1`,
      [teacherId, studentId, origin.id]
    );
    if (alreadyMakeup.rows.length > 0) {
      return { errorStatus: 400, errorMessage: 'Этот пропуск уже отработан' };
    }
    const originDate = String(origin.lesson_date || '').slice(0, 10);
    return { originLessonId: origin.id, originLessonDate: originDate || null };
  }

  await lockMakeupForStudent(client, { teacherId, studentId });
  const pendingResult = await client.query(
    `SELECT l.id, l.lesson_date
     FROM lessons l
     WHERE l.student_id = $1
       AND l.created_by = $2
       AND l.status IN ('missed', 'cancel_same_day')
       AND NOT EXISTS (
         SELECT 1
         FROM lessons m
         WHERE m.created_by = l.created_by
           AND m.student_id = l.student_id
           AND m.status = 'makeup'
           AND m.origin_lesson_id = l.id
       )
     ORDER BY l.lesson_date ASC, l.lesson_time ASC NULLS LAST, l.id ASC
     LIMIT 1`,
    [studentId, teacherId]
  );
  if (pendingResult.rows.length === 0) {
    return { errorStatus: 400, errorMessage: 'Для отработки не найден неотработанный пропуск/отмена в день' };
  }
  const row = pendingResult.rows[0];
  return {
    originLessonId: row.id,
    originLessonDate: String(row.lesson_date || '').slice(0, 10) || null,
  };
};

// Получение всех занятий студента
export const getStudentLessons = async (req, res) => {
  try {
    const userId = req.user.userId;
    const studentId = parsePositiveInt(req.params?.studentId); // L9
    if (!studentId) {
      return res.status(400).json({ message: 'Некорректный ID ученика' });
    }
    const mine = req.query.mine === '1' || req.query.mine === 'true';
    const pagination = parseLimitOffset(req); // M17
    if (pagination.error) {
      return res.status(400).json({ message: pagination.error });
    }

    // Суперпользователь (бухгалтерия) может смотреть занятия любого ученика
    // Но для UI-автоподстановок (например, цена в отчетах) иногда нужно строго "мои занятия",
    // даже если роль суперпользователь.
    if (!isSuperuser(req.user) || mine) {
      const checkResult = await pool.query(
        'SELECT 1 FROM teacher_students WHERE teacher_id = $1 AND student_id = $2 LIMIT 1',
        [userId, studentId]
      );

      if (checkResult.rows.length === 0) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
    }

    const onlyMine = mine || !isSuperuser(req.user);
    // M17: собираем параметры и опциональный LIMIT/OFFSET один раз и переиспользуем
    // и в основном запросе, и в fallback (совместимость со старыми БД).
    const params = onlyMine ? [studentId, userId] : [studentId];
    const ownerFilter = onlyMine
      ? 'WHERE l.student_id = $1 AND l.created_by = $2'
      : 'WHERE l.student_id = $1';
    const orderClause = 'ORDER BY l.lesson_date DESC, l.lesson_time DESC NULLS LAST';
    const pageClause = buildLimitOffsetSql(params, pagination);
    const linkSelect = `
      (SELECT rl.report_id FROM report_lessons rl WHERE rl.lesson_id = l.id ORDER BY rl.id DESC LIMIT 1) AS linked_report_id,
      (SELECT rep.report_date::text FROM report_lessons rl
        JOIN reports rep ON rep.id = rl.report_id AND rep.created_by = l.created_by
        WHERE rl.lesson_id = l.id ORDER BY rl.id DESC LIMIT 1) AS linked_report_date,
      (SELECT o.lesson_date::text FROM lessons o WHERE o.id = l.origin_lesson_id LIMIT 1) AS origin_lesson_date`;
    let result;
    try {
      result = await pool.query(
        `SELECT l.*, ${sqlUserAccountingNameOrEmpty('u')} AS teacher_username, ${linkSelect}
         FROM lessons l
         LEFT JOIN users u ON l.created_by = u.id
         ${ownerFilter}
         ${orderClause}${pageClause}`,
        params
      );
    } catch (error) {
      // Совместимость со старыми БД без таблиц отчётов/связок:
      // возвращаем занятия без полей linked_report_*.
      if (error?.code === '42P01') {
        result = await pool.query(
          `SELECT l.*, ${sqlUserAccountingNameOrEmpty('u')} AS teacher_username, NULL::int AS linked_report_id, NULL::text AS linked_report_date,
                  (SELECT o.lesson_date::text FROM lessons o WHERE o.id = l.origin_lesson_id LIMIT 1) AS origin_lesson_date
           FROM lessons l
           LEFT JOIN users u ON l.created_by = u.id
           ${ownerFilter}
           ${orderClause}${pageClause}`,
          params
        );
      } else {
        throw error;
      }
    }

    res.json(result.rows);
  } catch (error) {
    console.error('Ошибка получения занятий:', error);
    res.status(500).json({ message: 'Ошибка получения занятий' });
  }
};

/**
 * GET /students/calendar-summary?from=YYYY-MM-DD&to=YYYY-MM-DD
 * Количество занятий по дням.
 * Обычный пользователь — только свои (created_by).
 * Super — все занятия в периоде (как полный список учеников).
 */
export const getLessonsCalendarSummary = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { from, to } = req.query;
    // M16: строгая проверка реальных календарных дат (а не только regex).
    if (!from || !to || !isRealCalendarDate(String(from)) || !isRealCalendarDate(String(to))) {
      return res.status(400).json({ message: 'Укажите from и to в формате YYYY-MM-DD' });
    }
    // M16: from не позже to и ограниченный диапазон, чтобы не агрегировать всю таблицу lessons.
    if (String(from) > String(to)) {
      return res.status(400).json({ message: 'from должен быть не позже to' });
    }
    const spanDays =
      Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86400000) + 1;
    if (spanDays > MAX_CALENDAR_SPAN_DAYS) {
      return res.status(400).json({ message: `Слишком большой диапазон дат (максимум ${MAX_CALENDAR_SPAN_DAYS} дней)` });
    }
    const result = isSuperuser(req.user)
      ? await pool.query(
          `SELECT lesson_date::text AS date, COUNT(*)::int AS count
           FROM lessons
           WHERE lesson_date >= $1::date AND lesson_date <= $2::date
           GROUP BY lesson_date
           ORDER BY lesson_date`,
          [from, to]
        )
      : await pool.query(
          `SELECT lesson_date::text AS date, COUNT(*)::int AS count
           FROM lessons
           WHERE created_by = $1 AND lesson_date >= $2::date AND lesson_date <= $3::date
           GROUP BY lesson_date
           ORDER BY lesson_date`,
          [userId, from, to]
        );
    return res.json({ days: result.rows });
  } catch (error) {
    console.error('getLessonsCalendarSummary:', error);
    return res.status(500).json({ message: 'Ошибка календаря занятий' });
  }
};

// Создание занятия 11
export const createLesson = async (req, res) => {
  const userId = req.user.userId;
  const student_id = parsePositiveInt(req.params?.studentId);
  const {
    lesson_date,
    lesson_time,
    duration_minutes,
    price,
    notes,
    status: rawStatus,
    origin_lesson_id,
  } = req.body;
  const idempotencyKey = getIdempotencyKey(req);
  const status = typeof rawStatus === 'string' ? rawStatus.trim() : 'attended';
  const originLessonId =
    origin_lesson_id == null || origin_lesson_id === ''
      ? null
      : parsePositiveInt(origin_lesson_id);

  // M13: приводим price к числу и округляем до 2 знаков (как round2 в депозитах).
  const priceNum = typeof price === 'string' ? parseFloat(price) : price;
  const priceFinal = Number.isFinite(priceNum) ? round2(priceNum) : null;

  // priceFinal <= 0 отсекает и цены, округляющиеся в 0 (например 0.004 → 0.00). (M13)
  if (!student_id || !lesson_date || priceFinal == null || priceFinal <= 0) {
    return res.status(400).json({ message: 'ID студента, дата и цена обязательны' });
  }
  if (priceFinal > MAX_MONEY_AMOUNT) {
    return res.status(400).json({ message: `Цена превышает допустимый максимум (${MAX_MONEY_AMOUNT} ₽)` });
  }
  // M16: реальная календарная дата (формат + существование даты).
  if (!isRealCalendarDate(String(lesson_date))) {
    return res.status(400).json({ message: 'lesson_date должен быть корректной датой в формате YYYY-MM-DD' });
  }
  if (!LESSON_STATUSES.has(status)) {
    return res.status(400).json({ message: 'Некорректный статус занятия' });
  }

  // M14: duration_minutes — целое число в диапазоне 1..1440 (по умолчанию 60).
  let durationFinal = 60;
  if (duration_minutes != null && duration_minutes !== '') {
    const d =
      typeof duration_minutes === 'number'
        ? duration_minutes
        : parseInt(String(duration_minutes), 10);
    if (!Number.isInteger(d) || d < 1 || d > 1440) {
      return res.status(400).json({ message: 'duration_minutes должен быть целым числом от 1 до 1440' });
    }
    durationFinal = d;
  }

  // M14: lesson_time — формат HH:MM[:SS], допускаем null.
  const lessonTimeRaw =
    lesson_time == null || lesson_time === '' ? null : String(lesson_time).trim();
  if (lessonTimeRaw != null && !isValidLessonTime(lessonTimeRaw)) {
    return res.status(400).json({ message: 'lesson_time должен быть в формате HH:MM' });
  }

  // M14: notes — та же санитизация, что и у описания депозита, плюс ограничение длины.
  let notesFinal = null;
  if (notes != null) {
    const cleanedNotes = sanitizeMessageContent(String(notes)).trim();
    notesFinal = cleanedNotes ? cleanedNotes.slice(0, NOTES_MAX_LENGTH) : null;
  }

  // M15: «сегодня» в таймзоне пользователя (как в отчётах) — до транзакции (отдельное соединение).
  let todayIso;
  try {
    const tz = await getUserTimeZone(pool, userId);
    todayIso = getDateInTimeZoneISO(tz);
  } catch (e) {
    console.error('createLesson: не удалось определить дату пользователя:', e);
    return res.status(500).json({ message: 'Ошибка определения даты. Проверьте миграции (колонка users.timezone).' });
  }
  // M15: запрещаем занятия на будущую дату.
  if (String(lesson_date) > todayIso) {
    return res.status(400).json({ message: 'Нельзя создать занятие на будущую дату' });
  }
  // M15: «отмена в день занятия» возможна только на сегодняшнюю дату.
  if (status === 'cancel_same_day' && String(lesson_date) !== todayIso) {
    return res.status(400).json({ message: 'Отмену «в день занятия» можно отметить только на сегодняшнюю дату' });
  }

  // Создание урока + транзакции должно быть атомарным
  const client = await pool.connect();
  let committed = false;
  try {
    try { await client.query('ROLLBACK'); } catch (_) {}
    await client.query('BEGIN');
    const idem = await beginIdempotent(client, {
      userId,
      scope: 'lessons:create',
      key: idempotencyKey,
      requestHash: hashIdempotencyPayload({
        student_id,
        lesson_date,
        lesson_time: lessonTimeRaw,
        duration_minutes: durationFinal,
        price: priceFinal,
        notes: notesFinal,
        status,
        origin_lesson_id: originLessonId,
      }),
    });
    if (idem.replay) {
      await client.query('ROLLBACK');
      return res.status(idem.responseStatus).json(idem.responseBody);
    }
    if (idem.conflict) {
      await client.query('ROLLBACK');
      return res.status(409).json({ message: idem.conflict });
    }

    // Проверяем, что студент доступен пользователю
    const can = await hasStudentAccess(client, userId, student_id);
    if (!can) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Студент не найден' });
    }

    // Защита от дубля: тот же студент, дата, время (или NULL) у того же владельца
    const lessonTimeValue = lessonTimeRaw;
    // Сериализуем конкурентные createLesson для одного user/student/date/time,
    // чтобы параллельные запросы не проходили dup-check одновременно.
    await client.query(
      'SELECT pg_advisory_xact_lock(hashtext($1))',
      [`lesson:create:${userId}:${student_id}:${lesson_date}:${lessonTimeValue ?? 'null'}`]
    );
    const dupCheck = await client.query(
      `SELECT id FROM lessons
       WHERE student_id = $1
         AND lesson_date = $2
         AND lesson_time IS NOT DISTINCT FROM $3
         AND created_by = $4
       LIMIT 1`,
      [student_id, lesson_date, lessonTimeValue, userId]
    );
    if (dupCheck.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ message: 'Занятие на эту дату/время уже существует' });
    }

    let isChargeable = true;
    let finalOriginLessonId = originLessonId;
    let makeupOriginDate = null;
    if (status === 'missed') {
      isChargeable = false;
    } else if (status === 'cancel_same_day') {
      // 1 отмена в день проведения бесплатна для каждой пары ученик+преподаватель.
      await client.query(
        `SELECT id
         FROM students
         WHERE id = $1
         FOR UPDATE`,
        [student_id]
      );
      const freeUsed = await client.query(
        `SELECT id
         FROM lessons
         WHERE student_id = $1
           AND created_by = $2
           AND status = 'cancel_same_day'
           AND is_chargeable = false
         LIMIT 1`,
        [student_id, userId]
      );
      isChargeable = freeUsed.rows.length > 0;
    }

    if (status === 'makeup') {
      const originResolved = await resolveMakeupOrigin(client, {
        studentId: student_id,
        teacherId: userId,
        originLessonId,
      });
      if (originResolved.errorMessage) {
        await client.query('ROLLBACK');
        return res.status(originResolved.errorStatus || 400).json({ message: originResolved.errorMessage });
      }
      finalOriginLessonId = originResolved.originLessonId;
      makeupOriginDate = originResolved.originLessonDate;
      // Отработка платная: создаем стандартное lesson-списание.
      isChargeable = true;
    }

    // Создаем занятие
    const lessonResult = await client.query(
      `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, status, is_chargeable, origin_lesson_id, notes, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING *`,
      [
        student_id,
        lesson_date,
        lessonTimeValue,
        durationFinal,
        priceFinal,
        status,
        isChargeable,
        finalOriginLessonId,
        notesFinal,
        userId,
      ]
    );

    const lesson = lessonResult.rows[0];

    if (isChargeable) {
      await client.query(
        `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
         VALUES ($1, $2, 'lesson', $3, $4, $5)`,
        [
          student_id,
          priceFinal,
          status === 'makeup' && makeupOriginDate
            ? `Занятие ${lesson_date}${lessonTimeValue ? ' в ' + lessonTimeValue : ''} (отработка за пропуск ${makeupOriginDate})`
            : `Занятие ${lesson_date}${lessonTimeValue ? ' в ' + lessonTimeValue : ''}`,
          lesson.id,
          userId,
        ]
      );
    }
    await completeIdempotent(client, {
      userId,
      scope: 'lessons:create',
      key: idempotencyKey,
      responseStatus: 201,
      responseBody: lesson,
    });
    await logAccountingEvent({
      userId,
      eventType: 'lesson_created',
      entityType: 'lesson',
      entityId: lesson.id,
      payload: {
        studentId: student_id,
        lessonDate: lesson_date,
        lessonTime: lessonTimeValue,
        price: priceFinal,
        status,
        isChargeable,
      },
    });

    await syncNoReportLessonIncome(client, lesson.id, userId);

    await client.query('COMMIT');
    committed = true;
    return res.status(201).json(lesson);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    if (error?.code === '23505') {
      if (isMakeupOriginUniqueViolation(error)) {
        return res.status(400).json({ message: 'Этот пропуск уже отработан' });
      }
      return res.status(409).json({ message: 'Занятие на эту дату/время уже существует' });
    }
    console.error('Ошибка создания занятия:', error);
    return res.status(500).json({ message: 'Ошибка создания занятия' });
  } finally {
    // L11: не делаем повторный ROLLBACK после успешного COMMIT.
    if (!committed) {
      try { await client.query('ROLLBACK'); } catch (_) {}
    }
    client.release();
  }
};

// Удаление занятия
export const deleteLesson = async (req, res) => {
  const userId = req.user.userId;
  const superuser = isSuperuser(req.user);
  const id = parsePositiveInt(req.params.id);
  if (!id) {
    return res.status(400).json({ message: 'Некорректный id занятия' });
  }

  const client = await pool.connect();
  let committed = false;
  try {
    try { await client.query('ROLLBACK'); } catch (_) {}
    await client.query('BEGIN');

    // Обычный пользователь может удалять только свои занятия,
    // суперпользователь — любые.
    const checkResult = superuser
      ? await client.query(
          `SELECT id, student_id, created_by, status, is_chargeable FROM lessons WHERE id = $1`,
          [id]
        )
      : await client.query(
          `SELECT id, student_id, created_by, status, is_chargeable FROM lessons WHERE id = $1 AND created_by = $2`,
          [id, userId]
        );

    if (checkResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Занятие не найдено' });
    }
    const lessonRow = checkResult.rows[0];

    // Занятия, привязанные к отчетам, удалять нельзя:
    // иначе отчет останется с "пустым" содержимым и нарушенной связностью.
    const linkedReportResult = await client.query(
      `SELECT rl.report_id
       FROM report_lessons rl
       WHERE rl.lesson_id = $1
       LIMIT 1`,
      [id]
    );
    if (linkedReportResult.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        message: 'Нельзя удалить занятие, привязанное к отчету. Сначала измените или удалите отчет.',
      });
    }

    // M20: нельзя удалить занятие, на которое ссылается отработка (makeup):
    // иначе origin_lesson_id отработки обнулится (ON DELETE SET NULL) и связь «пропуск→отработка»
    // осиротеет. Зеркалим защиту занятий, привязанных к отчёту.
    const makeupRefResult = await client.query(
      `SELECT 1 FROM lessons WHERE origin_lesson_id = $1 AND status = 'makeup' LIMIT 1`,
      [id]
    );
    if (makeupRefResult.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        message: 'Нельзя удалить занятие: на него ссылается отработка. Сначала удалите отработку.',
      });
    }

    // M19: право на одну бесплатную отмену «в день» выводится из наличия бесплатной строки
    // cancel_same_day (is_chargeable = false). Удаление такой строки при наличии платной отмены
    // у той же пары ученик+преподаватель повторно открыло бы это право (цикл создать-удалить =
    // бесконечные бесплатные отмены). Блокируем такое удаление без изменения схемы.
    if (lessonRow.status === 'cancel_same_day' && lessonRow.is_chargeable === false) {
      const dependentChargeable = await client.query(
        `SELECT 1 FROM lessons
         WHERE student_id = $1
           AND created_by = $2
           AND status = 'cancel_same_day'
           AND is_chargeable = true
         LIMIT 1`,
        [lessonRow.student_id, lessonRow.created_by]
      );
      if (dependentChargeable.rows.length > 0) {
        await client.query('ROLLBACK');
        return res.status(409).json({
          message: 'Нельзя удалить бесплатную отмену: у ученика есть платная отмена, зависящая от использованного права на бесплатную отмену.',
        });
      }
    }

    // Удаляем все транзакции, связанные с занятием.
    // Это важно для суперпользователя, чтобы не оставлять "висячие" lesson-списания.
    await deleteLessonIncomeForLesson(client, id);
    await client.query('DELETE FROM transactions WHERE lesson_id = $1', [id]);

    // Удаляем занятие (с тем же ограничением прав, что и на этапе проверки).
    if (superuser) {
      await client.query('DELETE FROM lessons WHERE id = $1', [id]);
    } else {
      await client.query('DELETE FROM lessons WHERE id = $1 AND created_by = $2', [id, userId]);
    }
    await logAccountingEvent({
      userId,
      eventType: 'lesson_deleted',
      entityType: 'lesson',
      entityId: id,
      payload: {},
    });

    await client.query('COMMIT');
    committed = true;
    return res.json({ message: 'Занятие удалено' });
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка удаления занятия:', error);
    return res.status(500).json({ message: 'Ошибка удаления занятия' });
  } finally {
    // L11: не делаем повторный ROLLBACK после успешного COMMIT.
    if (!committed) {
      try { await client.query('ROLLBACK'); } catch (_) {}
    }
    client.release();
  }
};

