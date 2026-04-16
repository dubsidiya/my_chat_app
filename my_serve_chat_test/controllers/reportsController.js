import pool from '../db.js';
import {
  beginIdempotent,
  completeIdempotent,
  getIdempotencyKey,
  hashIdempotencyPayload,
} from '../utils/idempotency.js';
import { logAccountingEvent } from '../utils/accountingAudit.js';
import { isSuperuser } from '../middleware/auth.js';
import {
  buildReportContentFromSlots,
  getTodayByUserTimezone,
  isValidISODate,
  normalizeSlots,
  parseReportContent,
  resolveChargeableByStatus,
  toMinutes,
  validateSlots,
} from '../services/reports/reportHelpers.js';
import {
  findAllReportsByUser,
  findMonthlyBreakdown,
  findMonthlyLessonCountsByPrice,
  findMonthlyNoReportAmount,
  findMonthlyTotals,
  findReportByIdForViewer,
  findReportLessons,
  findReportsList,
  findUserEmailById,
  markReportAsNotLate,
} from '../repositories/reports/reportsRepository.js';
import {
  validateMonthlySalaryQuery,
  validateReportInput,
} from '../validators/reports/reportValidator.js';

// Получение всех отчетов пользователя
export const getAllReports = async (req, res) => {
  try {
    const userId = req.user.userId;

    const result = await findAllReportsByUser(pool, userId);

    res.json(result.rows);
  } catch (error) {
    console.error('Ошибка получения отчетов:', error);
    res.status(500).json({ message: 'Ошибка получения отчетов' });
  }
};

/**
 * Список всех отчётов для бухгалтера/суперпользователя: кто сдал, какие поздние, фильтры по дате.
 * GET /reports/list?date_from=YYYY-MM-DD&date_to=YYYY-MM-DD&is_late=true|false
 * Только суперпользователь.
 */
export const getReportsList = async (req, res) => {
  if (!isSuperuser(req.user)) {
    return res.status(403).json({ message: 'Требуется доступ суперпользователя' });
  }
  try {
    const dateFrom = req.query.date_from;
    const dateTo = req.query.date_to;
    const isLate = req.query.is_late; // 'true' | 'false' | не задан

    const result = await findReportsList(pool, { dateFrom, dateTo, isLate });

    const rows = result.rows.map((row) => ({
      id: row.id,
      report_date: row.report_date,
      content: row.content,
      is_late: row.is_late,
      created_by: row.created_by,
      created_by_email: row.created_by_email || '',
      created_at: row.created_at,
      updated_at: row.updated_at,
      lessons_count: row.lessons_count ?? 0,
    }));

    res.json(rows);
  } catch (error) {
    console.error('getReportsList:', error);
    res.status(500).json({ message: 'Ошибка получения списка отчётов' });
  }
};

// Зарплата за месяц: 50% от дохода; поздние отчёты не входят в доход (считаем как 0)
export const getMonthlySalaryReport = async (req, res) => {
  try {
    const userId = req.user.userId;
    const validated = validateMonthlySalaryQuery({ year: req.query.year, month: req.query.month });
    if (validated.error) {
      return res.status(400).json({ message: validated.error });
    }
    const { year, month } = validated;
    const firstDay = `${year}-${String(month).padStart(2, '0')}-01`;
    const lastDay = new Date(year, month, 0);
    const lastDayStr = lastDay.getFullYear() + '-' +
      String(lastDay.getMonth() + 1).padStart(2, '0') + '-' +
      String(lastDay.getDate()).padStart(2, '0');

    // Доход за месяц по всем занятиям преподавателя (lesson_date в месяце)
    const totalsResult = await findMonthlyTotals(pool, { userId, firstDay, lastDayStr });
    const row = totalsResult.rows[0];
    const totalAll = Number(row?.total_all ?? 0);
    const lateAmount = Number(row?.late_amount ?? 0);
    const incomeCounted = Number(row?.income_counted ?? 0);
    const salary = Math.round(incomeCounted * 0.5);

    // Разбивка по отчётам за месяц (дата, поздний/нет, сумма)
    const breakdownResult = await findMonthlyBreakdown(pool, { userId, firstDay, lastDayStr });
    const reportBreakdown = breakdownResult.rows.map((r) => ({
      report_id: r.report_id,
      report_date: r.report_date,
      is_late: r.is_late,
      amount: Number(r.amount),
    }));

    // Занятия без отчёта (ручные) за этот месяц — входят в доход
    const noReportResult = await findMonthlyNoReportAmount(pool, { userId, firstDay, lastDayStr });
    const lessonsWithoutReportAmount = Number(noReportResult.rows[0]?.amount ?? 0);

    const byPriceResult = await findMonthlyLessonCountsByPrice(pool, { userId, firstDay, lastDayStr });
    const lessonsByPrice = byPriceResult.rows.map((p) => ({
      price: Number(p.price),
      lessons_count: p.lessons_count,
    }));

    res.json({
      year,
      month,
      first_day: firstDay,
      last_day: lastDayStr,
      total_all: totalAll,
      late_reports_amount: lateAmount,
      income_counted: incomeCounted,
      salary,
      report_breakdown: reportBreakdown,
      lessons_without_report_amount: lessonsWithoutReportAmount,
      lessons_by_price: lessonsByPrice,
    });
  } catch (error) {
    console.error('Ошибка расчёта зарплаты за месяц:', error);
    res.status(500).json({ message: 'Ошибка расчёта зарплаты за месяц' });
  }
};

// Получение одного отчета с занятиями
export const getReport = async (req, res) => {
  try {
    const userId = req.user.userId;
    const isSuper = isSuperuser(req.user);
    const { id } = req.params;

    const reportResult = await findReportByIdForViewer(pool, { reportId: id, userId, isSuper });

    if (reportResult.rows.length === 0) {
      return res.status(404).json({ message: 'Отчет не найден' });
    }

    const report = reportResult.rows[0];
    const reportOwnerId = report.created_by;

    const lessonsResult = await findReportLessons(pool, id);

    report.lessons = lessonsResult.rows;
    report.lessons_count = lessonsResult.rows.length;
    if (isSuper && reportOwnerId != null) {
      const u = await findUserEmailById(pool, reportOwnerId);
      report.created_by_email = u.rows[0]?.email ?? '';
    }

    res.json(report);
  } catch (error) {
    console.error('Ошибка получения отчета:', error);
    res.status(500).json({ message: 'Ошибка получения отчета' });
  }
};

// Создание отчета и автоматическое создание занятий
export const createReport = async (req, res) => {
  const userId = req.user.userId;
  const { report_date, content, slots: rawSlots } = req.body;
  const idempotencyKey = getIdempotencyKey(req);

  const hasSlots = Array.isArray(rawSlots);
  const inputValidation = validateReportInput({
    reportDate: report_date,
    content,
    hasSlots,
  });
  if (inputValidation.error) {
    return res.status(400).json({ message: inputValidation.error });
  }

  // Дата/таймзона — до транзакции (отдельное соединение), чтобы ошибка/отсутствие колонки timezone не давала 25P02
  let tz;
  let todayIso;
  try {
    const todayResult = await getTodayByUserTimezone(pool, userId);
    tz = todayResult.tz;
    todayIso = todayResult.todayIso;
  } catch (e) {
    console.error('getTodayByUserTimezone:', e);
    return res.status(500).json({ message: 'Ошибка определения даты. Проверьте миграции (колонка users.timezone).' });
  }

  const client = await pool.connect();
  try {
    // Защита: если из пула пришёл client с незавершённой/aborted транзакцией,
    try { await client.query('ROLLBACK'); } catch (_) {}
    await client.query('BEGIN');

    const idem = await beginIdempotent(client, {
      userId,
      scope: 'reports:create',
      key: idempotencyKey,
      requestHash: hashIdempotencyPayload({
        report_date,
        content: content ?? null,
        slots: rawSlots ?? null,
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

    // todayIso уже получен выше через pool
    if (report_date > todayIso) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Нельзя создать отчет за будущую дату' });
    }

    // Защита от дубля: один отчет на дату на пользователя
    const existingReport = await client.query(
      'SELECT id FROM reports WHERE report_date = $1 AND created_by = $2 LIMIT 1',
      [report_date, userId]
    );
    if (existingReport.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ message: 'Отчет за эту дату уже существует' });
    }

    let finalContent = content;
    let parsedLessons = [];

    if (hasSlots) {
      const slots = normalizeSlots(rawSlots);
      const err = validateSlots(slots);
      if (err) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: err });
      }

      // Получаем имена студентов (только свои)
      const studentIds = [...new Set(slots.flatMap((s) => s.students.map((x) => parseInt(x.studentId, 10))))];
      const studentsResult = await client.query(
        `SELECT s.id, s.name
         FROM teacher_students ts
         JOIN students s ON s.id = ts.student_id
         WHERE ts.teacher_id = $1 AND s.id = ANY($2::int[])`,
        [userId, studentIds]
      );
      if (studentsResult.rows.length !== studentIds.length) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: 'В отчете есть ученики, которых нет в списке доступных' });
      }

      const idToName = new Map(studentsResult.rows.map((r) => [r.id, r.name]));
      finalContent = buildReportContentFromSlots(report_date, slots, idToName);

      // Преобразуем slots в список "уроков" как дальше ожидает логика вставок
      parsedLessons = slots.flatMap((slot) => {
        const durationMinutes = toMinutes(slot.timeEnd) - toMinutes(slot.timeStart);
        const timeStart = slot.timeStart;
        const timeEnd = slot.timeEnd;
        return slot.students.map((st) => ({
          studentId: parseInt(st.studentId, 10),
          studentName: idToName.get(parseInt(st.studentId, 10)) || '',
          price: typeof st.price === 'string' ? parseFloat(st.price) : st.price,
          status: typeof st.status === 'string' ? st.status.trim() : 'attended',
          originLessonId: st.originLessonId == null ? null : parseInt(st.originLessonId, 10),
          timeStart,
          timeEnd,
          lessonTimeHHMM: timeStart,
          durationMinutes,
          notes: null,
        }));
      });
    }

    // Создаем отчет
    const reportResult = await client.query(
      `INSERT INTO reports (report_date, content, created_by, is_late)
       VALUES ($1, $2, $3, ($1::date < $4::date))
       RETURNING *`,
      [report_date, finalContent, userId, todayIso]
    );

    const report = reportResult.rows[0];

    // Парсим содержание отчета (старый способ) если slots не передавали
    if (!hasSlots) {
      parsedLessons = parseReportContent(finalContent, report_date, userId);
    }

    // Создаем занятия для каждого найденного ученика
    const createdLessons = [];
    for (const item of parsedLessons) {
      const { price, notes } = item;
      const status = typeof item.status === 'string' ? item.status : 'attended';
      const originLessonId = item.originLessonId == null ? null : parseInt(item.originLessonId, 10);

      // studentId может прийти из slots напрямую
      let studentId = item.studentId;
      let studentName = item.studentName;

      if (!studentId) {
        const name = (item.studentName || '').trim();
        if (!name) continue;
        // Ищем студента ТОЛЬКО среди студентов пользователя
        let studentResult = await client.query(
          `SELECT s.id
           FROM teacher_students ts
           JOIN students s ON s.id = ts.student_id
           WHERE ts.teacher_id = $1 AND LOWER(TRIM(s.name)) = LOWER($2)
           LIMIT 1`,
          [userId, name]
        );
        if (studentResult.rows.length === 0) {
          const fuzzyResult = await client.query(
            `SELECT s.id
             FROM teacher_students ts
             JOIN students s ON s.id = ts.student_id
             WHERE ts.teacher_id = $1 AND LOWER(TRIM(s.name)) LIKE LOWER($2)
             ORDER BY LENGTH(TRIM(s.name)) ASC, s.id ASC
             LIMIT 2`,
            [userId, `%${name}%`]
          );
          if (fuzzyResult.rows.length === 1) {
            studentResult = fuzzyResult;
          }
        }
        if (studentResult.rows.length === 0) continue;
        studentId = studentResult.rows[0].id;
        studentName = name;
      }

      // Формируем время старта
      const lessonTime = item.lessonTimeHHMM ? String(item.lessonTimeHHMM).substring(0, 5) : null;
      
      // Формируем описание с временем
      let description = `Занятие ${report_date}`;
      if (item.timeStart && item.timeEnd) description += ` ${item.timeStart}-${item.timeEnd}`;
      if (status === 'cancel_same_day') description += ' (отмена в день)';
      if (status === 'missed') description += ' (пропуск)';
      if (status === 'makeup') description += ' (отработка)';

      if (status === 'makeup' && originLessonId) {
        const originResult = await client.query(
          `SELECT id, student_id, status, created_by
           FROM lessons
           WHERE id = $1
           LIMIT 1`,
          [originLessonId]
        );
        if (originResult.rows.length === 0) {
          if (hasSlots) {
            await client.query('ROLLBACK');
            return res.status(400).json({ message: 'Некорректный makeup: исходное занятие не найдено' });
          }
          continue;
        }
        const origin = originResult.rows[0];
        if (origin.student_id !== studentId) {
          if (hasSlots) {
            await client.query('ROLLBACK');
            return res.status(400).json({ message: 'Некорректный makeup: origin относится к другому ученику' });
          }
          continue;
        }
        if (String(origin.created_by) !== String(userId)) {
          if (hasSlots) {
            await client.query('ROLLBACK');
            return res.status(403).json({ message: 'Некорректный makeup: origin другого преподавателя' });
          }
          continue;
        }
        if (!['missed', 'cancel_same_day'].includes(origin.status)) {
          if (hasSlots) {
            await client.query('ROLLBACK');
            return res.status(400).json({ message: 'Некорректный makeup: origin должен быть missed/cancel_same_day' });
          }
          continue;
        }
      }
      const isChargeable = await resolveChargeableByStatus(client, { studentId, status, originLessonId });

      // Создаем занятие
      const lessonResult = await client.query(
        `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, status, is_chargeable, origin_lesson_id, notes, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         RETURNING *`,
        [
          studentId,
          report_date,
          lessonTime,
          item.durationMinutes || 60,
          price,
          status,
          isChargeable,
          originLessonId,
          notes || null,
          userId,
        ]
      );

      const lesson = lessonResult.rows[0];

      if (isChargeable) {
        await client.query(
          `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
           VALUES ($1, $2, 'lesson', $3, $4, $5)`,
          [studentId, price, description, lesson.id, userId]
        );
      }

      // Связываем занятие с отчетом
      await client.query(
        `INSERT INTO report_lessons (report_id, lesson_id)
         VALUES ($1, $2)`,
        [report.id, lesson.id]
      );

      createdLessons.push({ ...lesson, student_name: studentName });
    }

    report.lessons = createdLessons;
    report.lessons_count = createdLessons.length;
    report.parsed_count = parsedLessons.length;
    report.created_count = createdLessons.length;

    await completeIdempotent(client, {
      userId,
      scope: 'reports:create',
      key: idempotencyKey,
      responseStatus: 201,
      responseBody: report,
    });
    // Аудит на отдельном соединении, чтобы ошибка/отсутствие audit_events не переводило транзакцию в 25P02
    await logAccountingEvent({
      userId,
      eventType: 'report_created',
      entityType: 'report',
      entityId: report.id,
      payload: {
        reportDate: report_date,
        lessonsCreated: createdLessons.length,
        timezone: tz,
      },
    });

    await client.query('COMMIT');
    return res.status(201).json(report);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    if (error?.code === '23505') {
      return res.status(409).json({ message: 'Конфликт данных: возможно дубликат отчета или занятия' });
    }
    await logAccountingEvent({
      userId,
      eventType: 'report_create_error',
      entityType: 'report',
      entityId: null,
      payload: {
        code: error?.code || null,
        constraint: error?.constraint || null,
        detail: error?.detail || null,
        where: error?.where || null,
        report_date: req.body?.report_date || null,
        has_slots: Array.isArray(req.body?.slots),
      },
    });
    // Даем пользователю минимально полезную диагностику, без stack trace.
    if (error?.code === '42P01') {
      return res.status(500).json({ message: 'Ошибка создания отчета: БД не мигрирована (нет таблицы/индекса). Примените миграции.' });
    }
    if (error?.code === '42501') {
      return res.status(500).json({ message: 'Ошибка создания отчета: недостаточно прав на объекты БД. Проверьте роль пользователя БД и миграции.' });
    }
    console.error('Ошибка создания отчета:', error);
    return res.status(500).json({ message: 'Ошибка создания отчета' });
  } finally {
    // Страховка: никогда не возвращаем client в пул в aborted состоянии.
    try { await client.query('ROLLBACK'); } catch (_) {}
    client.release();
  }
};

// Обновление отчета (удаляет старые занятия и создает новые)
export const updateReport = async (req, res) => {
  const userId = req.user.userId;
  const superuser = isSuperuser(req.user);
  const { id } = req.params;
  const { report_date, content, slots: rawSlots } = req.body;

  const hasSlots = Array.isArray(rawSlots);
  const inputValidation = validateReportInput({
    reportDate: report_date,
    content,
    hasSlots,
  });
  if (inputValidation.error) {
    return res.status(400).json({ message: inputValidation.error });
  }

  let tz;
  let todayIso;
  try {
    const todayResult = await getTodayByUserTimezone(pool, userId);
    tz = todayResult.tz;
    todayIso = todayResult.todayIso;
  } catch (e) {
    console.error('getTodayByUserTimezone:', e);
    return res.status(500).json({ message: 'Ошибка определения даты. Проверьте миграции (колонка users.timezone).' });
  }

  const client = await pool.connect();
  try {
    try { await client.query('ROLLBACK'); } catch (_) {}
    await client.query('BEGIN');
    // todayIso уже получен выше через pool
    if (report_date > todayIso) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Нельзя установить будущую дату отчета' });
    }

    // Автор может редактировать свой отчёт, суперпользователь — любой.
    const checkResult = superuser
      ? await client.query(
          'SELECT id, created_by FROM reports WHERE id = $1 LIMIT 1',
          [id]
        )
      : await client.query(
          'SELECT id, created_by FROM reports WHERE id = $1 AND created_by = $2',
          [id, userId]
        );
    if (checkResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Отчет не найден' });
    }
    const reportOwnerId = checkResult.rows[0].created_by;

    // Защита от конфликта даты: нельзя сменить дату на уже существующий отчет
    const dateConflict = await client.query(
      'SELECT id FROM reports WHERE report_date = $1 AND created_by = $2 AND id <> $3 LIMIT 1',
      [report_date, reportOwnerId, id]
    );
    if (dateConflict.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ message: 'Отчет за эту дату уже существует' });
    }

    // Получаем старые занятия из отчета
    const oldLessonsResult = await client.query(
      `SELECT lesson_id FROM report_lessons WHERE report_id = $1`,
      [id]
    );
    const oldLessonIds = oldLessonsResult.rows.map((row) => row.lesson_id);

    // Удаляем старые транзакции и занятия (только свои)
    if (oldLessonIds.length > 0) {
      await client.query(
        'DELETE FROM transactions WHERE created_by = $1 AND lesson_id = ANY($2::int[])',
        [reportOwnerId, oldLessonIds]
      );
      await client.query(
        'DELETE FROM lessons WHERE created_by = $1 AND id = ANY($2::int[])',
        [reportOwnerId, oldLessonIds]
      );
    }

    // Удаляем связи
    await client.query('DELETE FROM report_lessons WHERE report_id = $1', [id]);

    let finalContent = content;
    let parsedLessons = [];

    if (hasSlots) {
      const slots = normalizeSlots(rawSlots);
      const err = validateSlots(slots);
      if (err) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: err });
      }

      const studentIds = [...new Set(slots.flatMap((s) => s.students.map((x) => parseInt(x.studentId, 10))))];
      const studentsResult = await client.query(
        `SELECT s.id, s.name
         FROM teacher_students ts
         JOIN students s ON s.id = ts.student_id
         WHERE ts.teacher_id = $1 AND s.id = ANY($2::int[])`,
        [reportOwnerId, studentIds]
      );
      if (studentsResult.rows.length !== studentIds.length) {
        await client.query('ROLLBACK');
        return res.status(400).json({ message: 'В отчете есть ученики, которых нет в списке доступных' });
      }
      const idToName = new Map(studentsResult.rows.map((r) => [r.id, r.name]));
      finalContent = buildReportContentFromSlots(report_date, slots, idToName);
      parsedLessons = slots.flatMap((slot) => {
        const durationMinutes = toMinutes(slot.timeEnd) - toMinutes(slot.timeStart);
        const timeStart = slot.timeStart;
        const timeEnd = slot.timeEnd;
        return slot.students.map((st) => ({
          studentId: parseInt(st.studentId, 10),
          studentName: idToName.get(parseInt(st.studentId, 10)) || '',
          price: typeof st.price === 'string' ? parseFloat(st.price) : st.price,
          status: typeof st.status === 'string' ? st.status.trim() : 'attended',
          originLessonId: st.originLessonId == null ? null : parseInt(st.originLessonId, 10),
          timeStart,
          timeEnd,
          lessonTimeHHMM: timeStart,
          durationMinutes,
          notes: null,
        }));
      });
    }

    // Обновляем отчет. is_late меняем только суперпользователю.
    const reportResult = superuser
      ? await client.query(
          `UPDATE reports 
           SET report_date = $1, content = $2, updated_at = CURRENT_TIMESTAMP,
               is_late = ($1::date < $4::date)
           WHERE id = $3
           RETURNING *`,
          [report_date, finalContent, id, todayIso]
        )
      : await client.query(
          `UPDATE reports 
           SET report_date = $1, content = $2, updated_at = CURRENT_TIMESTAMP
           WHERE id = $3 AND created_by = $4
           RETURNING *`,
          [report_date, finalContent, id, reportOwnerId]
        );
    const report = reportResult.rows[0];

    // Парсим новое содержание и создаем занятия заново
    if (!hasSlots) {
      parsedLessons = parseReportContent(finalContent, report_date, reportOwnerId);
    }
    const createdLessons = [];

    for (const item of parsedLessons) {
      const { price, notes } = item;
      const status = typeof item.status === 'string' ? item.status : 'attended';
      const originLessonId = item.originLessonId == null ? null : parseInt(item.originLessonId, 10);

      let studentId = item.studentId;
      let studentName = item.studentName;

      if (!studentId) {
        const name = (item.studentName || '').trim();
        if (!name) continue;
        let studentResult = await client.query(
          `SELECT s.id
           FROM teacher_students ts
           JOIN students s ON s.id = ts.student_id
           WHERE ts.teacher_id = $1 AND LOWER(TRIM(s.name)) = LOWER($2)
           LIMIT 1`,
          [reportOwnerId, name]
        );
        if (studentResult.rows.length === 0) {
          const fuzzyResult = await client.query(
            `SELECT s.id
             FROM teacher_students ts
             JOIN students s ON s.id = ts.student_id
             WHERE ts.teacher_id = $1 AND LOWER(TRIM(s.name)) LIKE LOWER($2)
             ORDER BY LENGTH(TRIM(s.name)) ASC, s.id ASC
             LIMIT 2`,
            [reportOwnerId, `%${name}%`]
          );
          if (fuzzyResult.rows.length === 1) {
            studentResult = fuzzyResult;
          }
        }
        if (studentResult.rows.length === 0) continue;
        studentId = studentResult.rows[0].id;
        studentName = name;
      }

      const lessonTime = item.lessonTimeHHMM ? String(item.lessonTimeHHMM).substring(0, 5) : null;

      let description = `Занятие ${report_date}`;
      if (item.timeStart && item.timeEnd) description += ` ${item.timeStart}-${item.timeEnd}`;
      if (status === 'cancel_same_day') description += ' (отмена в день)';
      if (status === 'missed') description += ' (пропуск)';
      if (status === 'makeup') description += ' (отработка)';

      if (status === 'makeup' && originLessonId) {
        const originResult = await client.query(
          `SELECT id, student_id, status, created_by
           FROM lessons
           WHERE id = $1
           LIMIT 1`,
          [originLessonId]
        );
        if (originResult.rows.length === 0) {
          if (hasSlots) {
            await client.query('ROLLBACK');
            return res.status(400).json({ message: 'Некорректный makeup: исходное занятие не найдено' });
          }
          continue;
        }
        const origin = originResult.rows[0];
        if (origin.student_id !== studentId) {
          if (hasSlots) {
            await client.query('ROLLBACK');
            return res.status(400).json({ message: 'Некорректный makeup: origin относится к другому ученику' });
          }
          continue;
        }
        if (String(origin.created_by) !== String(reportOwnerId)) {
          if (hasSlots) {
            await client.query('ROLLBACK');
            return res.status(403).json({ message: 'Некорректный makeup: origin другого преподавателя' });
          }
          continue;
        }
        if (!['missed', 'cancel_same_day'].includes(origin.status)) {
          if (hasSlots) {
            await client.query('ROLLBACK');
            return res.status(400).json({ message: 'Некорректный makeup: origin должен быть missed/cancel_same_day' });
          }
          continue;
        }
      }
      const isChargeable = await resolveChargeableByStatus(client, { studentId, status, originLessonId });

      const lessonResult = await client.query(
        `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, status, is_chargeable, origin_lesson_id, notes, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         RETURNING *`,
        [
          studentId,
          report_date,
          lessonTime,
          item.durationMinutes || 60,
          price,
          status,
          isChargeable,
          originLessonId,
          notes || null,
          reportOwnerId,
        ]
      );
      const lesson = lessonResult.rows[0];

      if (isChargeable) {
        await client.query(
          `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
           VALUES ($1, $2, 'lesson', $3, $4, $5)`,
          [studentId, price, description, lesson.id, reportOwnerId]
        );
      }

      await client.query(
        `INSERT INTO report_lessons (report_id, lesson_id)
         VALUES ($1, $2)`,
        [report.id, lesson.id]
      );

      createdLessons.push({ ...lesson, student_name: studentName });
    }

    report.lessons = createdLessons;
    report.lessons_count = createdLessons.length;
    report.parsed_count = parsedLessons.length;
    report.created_count = createdLessons.length;
    // Аудит на отдельном соединении — не трогаем client-транзакцию
    await logAccountingEvent({
      userId,
      eventType: 'report_updated',
      entityType: 'report',
      entityId: id,
      payload: {
        reportDate: report_date,
        lessonsCreated: createdLessons.length,
        timezone: tz,
      },
    });

    await client.query('COMMIT');
    return res.json(report);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    if (error?.code === '23505') {
      return res.status(409).json({ message: 'Конфликт данных: возможно дубликат отчета или занятия' });
    }
    await logAccountingEvent({
      userId,
      eventType: 'report_update_error',
      entityType: 'report',
      entityId: id,
      payload: {
        code: error?.code || null,
        constraint: error?.constraint || null,
        detail: error?.detail || null,
        where: error?.where || null,
        report_date: req.body?.report_date || null,
        has_slots: Array.isArray(req.body?.slots),
      },
    });
    console.error('Ошибка обновления отчета:', error);
    return res.status(500).json({ message: 'Ошибка обновления отчета' });
  } finally {
    try { await client.query('ROLLBACK'); } catch (_) {}
    client.release();
  }
};

// Удаление отчета
export const deleteReport = async (req, res) => {
  const userId = req.user.userId;
  const { id } = req.params;

  const client = await pool.connect();
  try {
    try { await client.query('ROLLBACK'); } catch (_) {}
    await client.query('BEGIN');

    // Проверяем, что отчет принадлежит пользователю
    const checkResult = await client.query(
      'SELECT id FROM reports WHERE id = $1 AND created_by = $2',
      [id, userId]
    );
    if (checkResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Отчет не найден' });
    }

    // Получаем занятия из отчета
    const lessonsResult = await client.query(
      `SELECT lesson_id FROM report_lessons WHERE report_id = $1`,
      [id]
    );
    const lessonIds = lessonsResult.rows.map((r) => r.lesson_id);

    if (lessonIds.length > 0) {
      await client.query(
        'DELETE FROM transactions WHERE created_by = $1 AND lesson_id = ANY($2::int[])',
        [userId, lessonIds]
      );
      await client.query(
        'DELETE FROM lessons WHERE created_by = $1 AND id = ANY($2::int[])',
        [userId, lessonIds]
      );
    }

    // Удаляем отчет (каскадно удалит связи)
    await client.query('DELETE FROM reports WHERE id = $1 AND created_by = $2', [id, userId]);
    // Аудит на отдельном соединении
    await logAccountingEvent({
      userId,
      eventType: 'report_deleted',
      entityType: 'report',
      entityId: id,
      payload: {
        lessonsDeleted: lessonIds.length,
      },
    });

    await client.query('COMMIT');
    return res.json({ message: 'Отчет удален' });
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка удаления отчета:', error);
    return res.status(500).json({ message: 'Ошибка удаления отчета' });
  } finally {
    try { await client.query('ROLLBACK'); } catch (_) {}
    client.release();
  }
};

/**
 * Снять пометку «поздний отчёт» (только суперпользователь).
 * Позволяет засчитать отчёт в доход/зарплату, хотя он был сдан с опозданием.
 * PATCH /reports/:id/set-not-late
 * Защита: маршрут с requireSuperuser + повторная проверка в контроллере.
 */
export const setReportNotLate = async (req, res) => {
  if (!isSuperuser(req.user)) {
    return res.status(403).json({ message: 'Требуется доступ суперпользователя' });
  }
  const reportId = parseInt(req.params.id, 10);
  if (!Number.isFinite(reportId)) {
    return res.status(400).json({ message: 'Некорректный id отчёта' });
  }
  try {
    const result = await markReportAsNotLate(pool, reportId);
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Отчёт не найден' });
    }
    await logAccountingEvent({
      userId: req.user.userId,
      eventType: 'report_set_not_late',
      entityType: 'report',
      entityId: reportId,
      payload: { report_date: result.rows[0].report_date },
    });
    return res.json(result.rows[0]);
  } catch (error) {
    console.error('setReportNotLate:', error);
    return res.status(500).json({ message: 'Ошибка при снятии пометки «поздний отчёт»' });
  }
};

/**
 * Журнал аудита по отчёту (audit_events). Доступ: автор отчёта или суперпользователь.
 * GET /reports/:id/audit
 */
export const getReportAudit = async (req, res) => {
  const userId = req.user.userId;
  const id = parseInt(req.params.id, 10);
  if (!Number.isFinite(id)) {
    return res.status(400).json({ message: 'Некорректный id отчёта' });
  }
  try {
    const own = await pool.query(
      'SELECT id FROM reports WHERE id = $1 AND created_by = $2',
      [id, userId]
    );
    if (own.rows.length === 0) {
      if (!isSuperuser(req.user)) {
        return res.status(403).json({ message: 'Нет доступа к этому отчёту' });
      }
      const exists = await pool.query('SELECT id FROM reports WHERE id = $1', [id]);
      if (exists.rows.length === 0) {
        return res.status(404).json({ message: 'Отчёт не найден' });
      }
    }

    const result = await pool.query(
      `SELECT ae.id, ae.user_id, ae.event_type, ae.entity_type, ae.entity_id, ae.payload, ae.created_at,
              u.email AS user_email
       FROM audit_events ae
       LEFT JOIN users u ON u.id = ae.user_id
       WHERE ae.entity_type = 'report' AND ae.entity_id = $1
       ORDER BY ae.created_at DESC
       LIMIT 100`,
      [String(id)]
    );
    return res.json({ events: result.rows });
  } catch (error) {
    const msg = error?.message || String(error);
    if (/relation "audit_events" does not exist/i.test(msg)) {
      return res.json({ events: [], message: 'Таблица аудита не развёрнута на сервере' });
    }
    console.error('getReportAudit:', error);
    return res.status(500).json({ message: 'Ошибка загрузки журнала' });
  }
};

