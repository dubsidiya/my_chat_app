import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';
import { parsePositiveInt } from '../utils/sanitize.js';
import { sqlUserAccountingNameOrEmpty } from '../utils/userAccountingDisplaySql.js';
import {
  beginIdempotent,
  completeIdempotent,
  getIdempotencyKey,
  hashIdempotencyPayload,
} from '../utils/idempotency.js';
import { logAccountingEvent } from '../utils/accountingAudit.js';
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const LESSON_STATUSES = new Set(['attended', 'missed', 'makeup', 'cancel_same_day']);

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
    const { studentId } = req.params;
    const mine = req.query.mine === '1' || req.query.mine === 'true';

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
    const linkSelect = `
      (SELECT rl.report_id FROM report_lessons rl WHERE rl.lesson_id = l.id ORDER BY rl.id DESC LIMIT 1) AS linked_report_id,
      (SELECT rep.report_date::text FROM report_lessons rl
        JOIN reports rep ON rep.id = rl.report_id AND rep.created_by = l.created_by
        WHERE rl.lesson_id = l.id ORDER BY rl.id DESC LIMIT 1) AS linked_report_date,
      (SELECT o.lesson_date::text FROM lessons o WHERE o.id = l.origin_lesson_id LIMIT 1) AS origin_lesson_date`;
    let result;
    try {
      result = onlyMine
          ? await pool.query(
              `SELECT l.*, ${sqlUserAccountingNameOrEmpty('u')} AS teacher_username, ${linkSelect}
               FROM lessons l
               LEFT JOIN users u ON l.created_by = u.id
               WHERE l.student_id = $1 AND l.created_by = $2
               ORDER BY l.lesson_date DESC, l.lesson_time DESC NULLS LAST`,
              [studentId, userId]
            )
          : await pool.query(
              `SELECT l.*, ${sqlUserAccountingNameOrEmpty('u')} AS teacher_username, ${linkSelect}
               FROM lessons l
               LEFT JOIN users u ON l.created_by = u.id
               WHERE l.student_id = $1
               ORDER BY l.lesson_date DESC, l.lesson_time DESC NULLS LAST`,
              [studentId]
            );
    } catch (error) {
      // Совместимость со старыми БД без таблиц отчётов/связок:
      // возвращаем занятия без полей linked_report_*.
      if (error?.code === '42P01') {
        result = onlyMine
            ? await pool.query(
                `SELECT l.*, ${sqlUserAccountingNameOrEmpty('u')} AS teacher_username, NULL::int AS linked_report_id, NULL::text AS linked_report_date,
                        (SELECT o.lesson_date::text FROM lessons o WHERE o.id = l.origin_lesson_id LIMIT 1) AS origin_lesson_date
                 FROM lessons l
                 LEFT JOIN users u ON l.created_by = u.id
                 WHERE l.student_id = $1 AND l.created_by = $2
                 ORDER BY l.lesson_date DESC, l.lesson_time DESC NULLS LAST`,
                [studentId, userId]
              )
            : await pool.query(
                `SELECT l.*, ${sqlUserAccountingNameOrEmpty('u')} AS teacher_username, NULL::int AS linked_report_id, NULL::text AS linked_report_date,
                        (SELECT o.lesson_date::text FROM lessons o WHERE o.id = l.origin_lesson_id LIMIT 1) AS origin_lesson_date
                 FROM lessons l
                 LEFT JOIN users u ON l.created_by = u.id
                 WHERE l.student_id = $1
                 ORDER BY l.lesson_date DESC, l.lesson_time DESC NULLS LAST`,
                [studentId]
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
 * Количество занятий по дням для текущего пользователя (created_by).
 */
export const getLessonsCalendarSummary = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { from, to } = req.query;
    if (!from || !to || !ISO_DATE_RE.test(String(from)) || !ISO_DATE_RE.test(String(to))) {
      return res.status(400).json({ message: 'Укажите from и to в формате YYYY-MM-DD' });
    }
    const result = await pool.query(
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

  // Преобразуем price в число, если это строка
  const priceNum = typeof price === 'string' ? parseFloat(price) : price;

  if (!student_id || !lesson_date || !Number.isFinite(priceNum) || priceNum <= 0) {
    return res.status(400).json({ message: 'ID студента, дата и цена обязательны' });
  }
  if (!ISO_DATE_RE.test(String(lesson_date))) {
    return res.status(400).json({ message: 'lesson_date должен быть в формате YYYY-MM-DD' });
  }
  if (!LESSON_STATUSES.has(status)) {
    return res.status(400).json({ message: 'Некорректный статус занятия' });
  }

  // Создание урока + транзакции должно быть атомарным
  const client = await pool.connect();
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
        lesson_time: lesson_time || null,
        duration_minutes: duration_minutes || 60,
        price: priceNum,
        notes: notes || null,
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
    const lessonTimeValue = lesson_time || null;
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
      // 1 отмена в день проведения за всё время бесплатна, остальные платные.
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
           AND status = 'cancel_same_day'
           AND is_chargeable = false
         LIMIT 1`,
        [student_id]
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
        duration_minutes || 60,
        priceNum,
        status,
        isChargeable,
        finalOriginLessonId,
        notes || null,
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
          priceNum,
          status === 'makeup' && makeupOriginDate
            ? `Занятие ${lesson_date}${lesson_time ? ' в ' + lesson_time : ''} (отработка за пропуск ${makeupOriginDate})`
            : `Занятие ${lesson_date}${lesson_time ? ' в ' + lesson_time : ''}`,
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
        price: priceNum,
        status,
        isChargeable,
      },
    });

    await client.query('COMMIT');
    return res.status(201).json(lesson);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    if (error?.code === '23505') {
      return res.status(409).json({ message: 'Занятие на эту дату/время уже существует' });
    }
    console.error('Ошибка создания занятия:', error);
    return res.status(500).json({ message: 'Ошибка создания занятия' });
  } finally {
    try { await client.query('ROLLBACK'); } catch (_) {}
    client.release();
  }
};

// Удаление занятия
export const deleteLesson = async (req, res) => {
  const userId = req.user.userId;
  const superuser = isSuperuser(req.user);
  const { id } = req.params;

  const client = await pool.connect();
  try {
    try { await client.query('ROLLBACK'); } catch (_) {}
    await client.query('BEGIN');

    // Обычный пользователь может удалять только свои занятия,
    // суперпользователь — любые.
    const checkResult = superuser
      ? await client.query(
          `SELECT id FROM lessons WHERE id = $1`,
          [id]
        )
      : await client.query(
          `SELECT id FROM lessons WHERE id = $1 AND created_by = $2`,
          [id, userId]
        );

    if (checkResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Занятие не найдено' });
    }

    // Удаляем все транзакции, связанные с занятием.
    // Это важно для суперпользователя, чтобы не оставлять "висячие" lesson-списания.
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
    return res.json({ message: 'Занятие удалено' });
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка удаления занятия:', error);
    return res.status(500).json({ message: 'Ошибка удаления занятия' });
  } finally {
    try { await client.query('ROLLBACK'); } catch (_) {}
    client.release();
  }
};

