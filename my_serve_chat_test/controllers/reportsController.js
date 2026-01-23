import pool from '../db.js';

// Парсинг текста отчета для извлечения занятий
// Новый формат:
// 17 декабря
// за какой день отчет
// 14-16 Антон Нгуен 2.0 / Алексей курганский 2.0
// 16-18 Элина 2.0/ Иван удодов 2.1 ?????
// 18-20 Илья Мищенко 2.1/ Майкл 1.8
const parseReportContent = (content, reportDate, userId) => {
  const lines = content.split('\n').map(line => line.trim()).filter(line => line);
  const lessons = [];
  
  // Пропускаем первую строку с датой (например, "17 декабря")
  let startIndex = 0;
  if (lines.length > 0 && /^\d+\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)/i.test(lines[0])) {
    startIndex = 1;
  }

  for (let i = startIndex; i < lines.length; i++) {
    const line = lines[i];
    if (!line) continue;

    // Формат: "14-16 Антон Нгуен 2.0 / Алексей курганский 2.0"
    // или: "16-18 Элина 2.0/ Иван удодов 2.1 ??????"
    const timePattern = /^(\d{1,2})-(\d{1,2})\s+(.+)$/;
    const timeMatch = line.match(timePattern);
    
    if (!timeMatch) continue;

    const startTime = timeMatch[1];
    const endTime = timeMatch[2];
    const restOfLine = timeMatch[3];

    // Проверяем на отмену (??????)
    const isCancelled = /\?{3,}/.test(restOfLine);
    const cleanLine = restOfLine.replace(/\?{3,}/g, '').trim();

    // Разделяем учеников по "/"
    const students = cleanLine.split('/').map(s => s.trim()).filter(s => s);

    for (const studentStr of students) {
      // Ищем имя и цену в формате "Имя 2.0" или "Имя 2.1"
      // Цена может быть в формате: 2.0 = 2000, 2.1 = 2100, 1.8 = 1800
      const studentPattern = /^(.+?)\s+(\d+)\.(\d+)\s*$/;
      const studentMatch = studentStr.match(studentPattern);

      if (studentMatch) {
        const studentName = studentMatch[1].trim();
        const priceInt = parseInt(studentMatch[2]);
        const priceDec = parseInt(studentMatch[3]);
        
        // Преобразуем "2.0" в 2000, "2.1" в 2100, "1.8" в 1800
        const price = priceInt * 1000 + priceDec * 100;

        if (studentName && price > 0) {
          lessons.push({
            studentName,
            price,
            timeStart: startTime,
            timeEnd: endTime,
            isCancelled,
            notes: isCancelled ? 'Отмена в день проведения (оплачивается)' : null
          });
        }
      }
    }
  }

  return lessons;
};

// -----------------------------
// Структурные отчеты (конструктор)
// -----------------------------
const MAX_SLOTS_PER_DAY = 10;
const MAX_STUDENTS_PER_SLOT = 2;

const isValidTimeHHMM = (t) => typeof t === 'string' && /^([01]?\d|2[0-3]):[0-5]\d$/.test(t.trim());

const toMinutes = (t) => {
  const [h, m] = t.split(':').map((x) => parseInt(x, 10));
  return h * 60 + m;
};

const formatPriceK = (priceRub) => {
  const n = typeof priceRub === 'string' ? parseFloat(priceRub) : priceRub;
  if (!Number.isFinite(n)) return '0.0';
  return (n / 1000).toFixed(1);
};

const buildReportContentFromSlots = (reportDate, slots, studentIdToName) => {
  const lines = [];
  lines.push(String(reportDate));
  lines.push('');
  for (const slot of slots) {
    const start = slot.timeStart;
    const end = slot.timeEnd;
    const studentParts = (slot.students || []).map((s) => {
      const name = studentIdToName.get(s.studentId) || `ID:${s.studentId}`;
      return `${name} ${formatPriceK(s.price)}`;
    });
    lines.push(`${start}-${end} ${studentParts.join(' / ')}`.trim());
  }
  return lines.join('\n').trim();
};

const minutesToHHMM = (mins) => {
  const m = Math.max(0, Math.min(23 * 60 + 59, mins));
  const hh = String(Math.floor(m / 60)).padStart(2, '0');
  const mm = String(m % 60).padStart(2, '0');
  return `${hh}:${mm}`;
};

const normalizeSlots = (rawSlots) => {
  if (!Array.isArray(rawSlots)) return [];
  return rawSlots
    .map((s) => ({
      timeStart: typeof s?.timeStart === 'string' ? s.timeStart.trim() : '',
      timeEnd: typeof s?.timeEnd === 'string' ? s.timeEnd.trim() : '',
      students: Array.isArray(s?.students) ? s.students : [],
    }))
    .filter((s) => s.timeStart && s.timeEnd);
};

const validateSlots = (slots) => {
  if (!Array.isArray(slots) || slots.length === 0) {
    return 'Нужно добавить хотя бы одно занятие';
  }
  if (slots.length > MAX_SLOTS_PER_DAY) {
    return `Максимум ${MAX_SLOTS_PER_DAY} занятий в день`;
  }
  for (const slot of slots) {
    if (!isValidTimeHHMM(slot.timeStart) || !isValidTimeHHMM(slot.timeEnd)) {
      return 'Время должно быть в формате ЧЧ:ММ';
    }
    const a = toMinutes(slot.timeStart);
    const b = toMinutes(slot.timeEnd);
    if (b <= a) return 'Время окончания должно быть позже времени начала';
    if (!Array.isArray(slot.students) || slot.students.length === 0) {
      return 'В каждом времени должен быть выбран хотя бы один ученик';
    }
    if (slot.students.length > MAX_STUDENTS_PER_SLOT) {
      return `В одном времени максимум ${MAX_STUDENTS_PER_SLOT} ученика`;
    }
    const ids = slot.students.map((x) => x?.studentId).filter(Boolean);
    const unique = new Set(ids);
    if (ids.length !== unique.size) {
      return 'В одном времени нельзя выбрать одного и того же ученика дважды';
    }
    for (const st of slot.students) {
      const id = parseInt(st?.studentId, 10);
      const price = typeof st?.price === 'string' ? parseFloat(st.price) : st?.price;
      if (!id || Number.isNaN(id)) return 'Некорректный ученик в занятии';
      if (!Number.isFinite(price) || price <= 0) return 'Укажите стоимость для каждого ученика';
    }
  }
  return null;
};

// Получение всех отчетов пользователя
export const getAllReports = async (req, res) => {
  try {
    const userId = req.user.userId;

    const result = await pool.query(
      `SELECT r.*, COUNT(rl.lesson_id) as lessons_count
       FROM reports r
       LEFT JOIN report_lessons rl ON r.id = rl.report_id
       WHERE r.created_by = $1
       GROUP BY r.id
       ORDER BY r.report_date DESC, r.created_at DESC`,
      [userId]
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Ошибка получения отчетов:', error);
    res.status(500).json({ message: 'Ошибка получения отчетов' });
  }
};

// Получение одного отчета с занятиями
export const getReport = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { id } = req.params;

    // Получаем отчет
    const reportResult = await pool.query(
      'SELECT * FROM reports WHERE id = $1 AND created_by = $2',
      [id, userId]
    );

    if (reportResult.rows.length === 0) {
      return res.status(404).json({ message: 'Отчет не найден' });
    }

    const report = reportResult.rows[0];

    // Получаем связанные занятия
    const lessonsResult = await pool.query(
      `SELECT l.*, s.name as student_name
       FROM report_lessons rl
       JOIN lessons l ON rl.lesson_id = l.id AND l.created_by = $2
       JOIN students s ON l.student_id = s.id
       JOIN teacher_students ts ON ts.student_id = s.id AND ts.teacher_id = $2
       WHERE rl.report_id = $1
       ORDER BY l.lesson_date, l.lesson_time`,
      [id, userId]
    );

    report.lessons = lessonsResult.rows;
    report.lessons_count = lessonsResult.rows.length;

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

  const hasSlots = Array.isArray(rawSlots);
  if (!report_date || (!content && !hasSlots)) {
    return res.status(400).json({ message: 'Дата обязательна. Укажите либо content, либо slots' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Запрещаем отчеты за будущие даты
    const futureCheck = await client.query('SELECT ($1::date > CURRENT_DATE) as is_future', [report_date]);
    if (futureCheck.rows[0]?.is_future) {
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
          timeStart,
          timeEnd,
          lessonTimeHHMM: timeStart,
          durationMinutes,
          notes: null,
          isCancelled: false,
        }));
      });
    }

    // Создаем отчет
    const reportResult = await client.query(
      `INSERT INTO reports (report_date, content, created_by, is_late)
       VALUES ($1, $2, $3, ($1::date < CURRENT_DATE))
       RETURNING *`,
      [report_date, finalContent, userId]
    );

    const report = reportResult.rows[0];

    // Парсим содержание отчета (старый способ) если slots не передавали
    if (!hasSlots) {
      parsedLessons = parseReportContent(finalContent, report_date, userId);
    }

    // Создаем занятия для каждого найденного ученика
    const createdLessons = [];
    for (const item of parsedLessons) {
      const { price, notes, isCancelled } = item;

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
          studentResult = await client.query(
            `SELECT s.id
             FROM teacher_students ts
             JOIN students s ON s.id = ts.student_id
             WHERE ts.teacher_id = $1 AND LOWER(TRIM(s.name)) LIKE LOWER($2)
             LIMIT 1`,
            [userId, `%${name}%`]
          );
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
      if (isCancelled) {
        description += ' (отмена, оплачивается)';
      }

      // Создаем занятие
      const lessonResult = await client.query(
        `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, notes, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING *`,
        [
          studentId,
          report_date,
          lessonTime,
          item.durationMinutes || 60,
          price,
          notes || null,
          userId,
        ]
      );

      const lesson = lessonResult.rows[0];

      // Создаем транзакцию списания
      await client.query(
        `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
         VALUES ($1, $2, 'lesson', $3, $4, $5)`,
        [studentId, price, description, lesson.id, userId]
      );

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

    await client.query('COMMIT');
    return res.status(201).json(report);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка создания отчета:', error);
    return res.status(500).json({ message: 'Ошибка создания отчета' });
  } finally {
    client.release();
  }
};

// Обновление отчета (удаляет старые занятия и создает новые)
export const updateReport = async (req, res) => {
  const userId = req.user.userId;
  const { id } = req.params;
  const { report_date, content, slots: rawSlots } = req.body;

  const hasSlots = Array.isArray(rawSlots);
  if (!report_date || (!content && !hasSlots)) {
    return res.status(400).json({ message: 'Дата обязательна. Укажите либо content, либо slots' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Запрещаем отчеты за будущие даты
    const futureCheck = await client.query('SELECT ($1::date > CURRENT_DATE) as is_future', [report_date]);
    if (futureCheck.rows[0]?.is_future) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Нельзя установить будущую дату отчета' });
    }

    // Проверяем, что отчет принадлежит пользователю
    const checkResult = await client.query(
      'SELECT id FROM reports WHERE id = $1 AND created_by = $2',
      [id, userId]
    );
    if (checkResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Отчет не найден' });
    }

    // Защита от конфликта даты: нельзя сменить дату на уже существующий отчет
    const dateConflict = await client.query(
      'SELECT id FROM reports WHERE report_date = $1 AND created_by = $2 AND id <> $3 LIMIT 1',
      [report_date, userId, id]
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
        [userId, oldLessonIds]
      );
      await client.query(
        'DELETE FROM lessons WHERE created_by = $1 AND id = ANY($2::int[])',
        [userId, oldLessonIds]
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
        [userId, studentIds]
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
          timeStart,
          timeEnd,
          lessonTimeHHMM: timeStart,
          durationMinutes,
          notes: null,
          isCancelled: false,
        }));
      });
    }

    // Обновляем отчет
    const reportResult = await client.query(
      `UPDATE reports 
       SET report_date = $1, content = $2, is_late = ($1::date < CURRENT_DATE), updated_at = CURRENT_TIMESTAMP
       WHERE id = $3 AND created_by = $4
       RETURNING *`,
      [report_date, finalContent, id, userId]
    );
    const report = reportResult.rows[0];

    // Парсим новое содержание и создаем занятия заново
    if (!hasSlots) {
      parsedLessons = parseReportContent(finalContent, report_date, userId);
    }
    const createdLessons = [];

    for (const item of parsedLessons) {
      const { price, notes, isCancelled } = item;

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
          [userId, name]
        );
        if (studentResult.rows.length === 0) {
          studentResult = await client.query(
            `SELECT s.id
             FROM teacher_students ts
             JOIN students s ON s.id = ts.student_id
             WHERE ts.teacher_id = $1 AND LOWER(TRIM(s.name)) LIKE LOWER($2)
             LIMIT 1`,
            [userId, `%${name}%`]
          );
        }
        if (studentResult.rows.length === 0) continue;
        studentId = studentResult.rows[0].id;
        studentName = name;
      }

      const lessonTime = item.lessonTimeHHMM ? String(item.lessonTimeHHMM).substring(0, 5) : null;

      let description = `Занятие ${report_date}`;
      if (item.timeStart && item.timeEnd) description += ` ${item.timeStart}-${item.timeEnd}`;
      if (isCancelled) description += ' (отмена, оплачивается)';

      const lessonResult = await client.query(
        `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, notes, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING *`,
        [studentId, report_date, lessonTime, item.durationMinutes || 60, price, notes || null, userId]
      );
      const lesson = lessonResult.rows[0];

      await client.query(
        `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
         VALUES ($1, $2, 'lesson', $3, $4, $5)`,
        [studentId, price, description, lesson.id, userId]
      );

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

    await client.query('COMMIT');
    return res.json(report);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка обновления отчета:', error);
    return res.status(500).json({ message: 'Ошибка обновления отчета' });
  } finally {
    client.release();
  }
};

// Удаление отчета
export const deleteReport = async (req, res) => {
  const userId = req.user.userId;
  const { id } = req.params;

  const client = await pool.connect();
  try {
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

    await client.query('COMMIT');
    return res.json({ message: 'Отчет удален' });
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка удаления отчета:', error);
    return res.status(500).json({ message: 'Ошибка удаления отчета' });
  } finally {
    client.release();
  }
};

