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
       JOIN lessons l ON rl.lesson_id = l.id
       JOIN students s ON l.student_id = s.id
       WHERE rl.report_id = $1
       ORDER BY l.lesson_date, l.lesson_time`,
      [id]
    );

    report.lessons = lessonsResult.rows;

    res.json(report);
  } catch (error) {
    console.error('Ошибка получения отчета:', error);
    res.status(500).json({ message: 'Ошибка получения отчета' });
  }
};

// Создание отчета и автоматическое создание занятий
export const createReport = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { report_date, content } = req.body;

    if (!report_date || !content) {
      return res.status(400).json({ message: 'Дата и содержание отчета обязательны' });
    }

    // Создаем отчет
    const reportResult = await pool.query(
      `INSERT INTO reports (report_date, content, created_by)
       VALUES ($1, $2, $3)
       RETURNING *`,
      [report_date, content, userId]
    );

    const report = reportResult.rows[0];

    // Парсим содержание отчета
    const parsedLessons = parseReportContent(content, report_date, userId);

    // Создаем занятия для каждого найденного ученика
    const createdLessons = [];
    for (const { studentName, price, timeStart, timeEnd, isCancelled, notes } of parsedLessons) {
      // Ищем студента по имени (точное совпадение или частичное) - общий для всех преподавателей
      const studentResult = await pool.query(
        `SELECT id FROM students 
         WHERE LOWER(TRIM(name)) = LOWER($1) OR LOWER(TRIM(name)) LIKE LOWER($2)
         ORDER BY CASE WHEN LOWER(TRIM(name)) = LOWER($1) THEN 1 ELSE 2 END
         LIMIT 1`,
        [studentName.trim(), `%${studentName.trim()}%`]
      );

      if (studentResult.rows.length > 0) {
        const studentId = studentResult.rows[0].id;

        // Формируем время в формате ЧЧ:ММ
        const lessonTime = timeStart ? `${timeStart.padStart(2, '0')}:00` : null;
        
        // Формируем описание с временем
        let description = `Занятие ${report_date}`;
        if (timeStart && timeEnd) {
          description += ` ${timeStart}-${timeEnd}`;
        }
        if (isCancelled) {
          description += ' (отмена, оплачивается)';
        }

        // Создаем занятие
        const lessonResult = await pool.query(
          `INSERT INTO lessons (student_id, lesson_date, lesson_time, price, notes, created_by)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING *`,
          [studentId, report_date, lessonTime, price, notes || null, userId]
        );

        const lesson = lessonResult.rows[0];

        // Создаем транзакцию списания
        await pool.query(
          `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
           VALUES ($1, $2, 'lesson', $3, $4, $5)`,
          [
            studentId,
            price,
            description,
            lesson.id,
            userId
          ]
        );

        // Связываем занятие с отчетом
        await pool.query(
          `INSERT INTO report_lessons (report_id, lesson_id)
           VALUES ($1, $2)`,
          [report.id, lesson.id]
        );

        createdLessons.push({ ...lesson, student_name: studentName });
      }
    }

    report.lessons = createdLessons;
    report.parsed_count = parsedLessons.length;
    report.created_count = createdLessons.length;

    res.status(201).json(report);
  } catch (error) {
    console.error('Ошибка создания отчета:', error);
    res.status(500).json({ message: 'Ошибка создания отчета' });
  }
};

// Обновление отчета (удаляет старые занятия и создает новые)
export const updateReport = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { id } = req.params;
    const { report_date, content } = req.body;

    // Проверяем, что отчет принадлежит пользователю
    const checkResult = await pool.query(
      'SELECT id FROM reports WHERE id = $1 AND created_by = $2',
      [id, userId]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Отчет не найден' });
    }

    // Получаем старые занятия из отчета
    const oldLessonsResult = await pool.query(
      `SELECT lesson_id FROM report_lessons WHERE report_id = $1`,
      [id]
    );

    const oldLessonIds = oldLessonsResult.rows.map(row => row.lesson_id);

    // Удаляем старые транзакции и занятия
    for (const lessonId of oldLessonIds) {
      // Удаляем транзакцию
      await pool.query('DELETE FROM transactions WHERE lesson_id = $1', [lessonId]);
      // Удаляем занятие
      await pool.query('DELETE FROM lessons WHERE id = $1', [lessonId]);
    }

    // Удаляем связи
    await pool.query('DELETE FROM report_lessons WHERE report_id = $1', [id]);

    // Обновляем отчет
    const reportResult = await pool.query(
      `UPDATE reports 
       SET report_date = $1, content = $2, updated_at = CURRENT_TIMESTAMP
       WHERE id = $3
       RETURNING *`,
      [report_date, content, id]
    );

    const report = reportResult.rows[0];

    // Парсим новое содержание и создаем занятия заново
    const parsedLessons = parseReportContent(content, report_date, userId);
    const createdLessons = [];

    for (const { studentName, price, timeStart, timeEnd, isCancelled, notes } of parsedLessons) {
      // Ищем студента по имени (общий для всех преподавателей)
      const studentResult = await pool.query(
        `SELECT id FROM students 
         WHERE LOWER(TRIM(name)) = LOWER($1) OR LOWER(TRIM(name)) LIKE LOWER($2)
         ORDER BY CASE WHEN LOWER(TRIM(name)) = LOWER($1) THEN 1 ELSE 2 END
         LIMIT 1`,
        [studentName.trim(), `%${studentName.trim()}%`]
      );

      if (studentResult.rows.length > 0) {
        const studentId = studentResult.rows[0].id;

        // Формируем время в формате ЧЧ:ММ
        const lessonTime = timeStart ? `${timeStart.padStart(2, '0')}:00` : null;
        
        // Формируем описание с временем
        let description = `Занятие ${report_date}`;
        if (timeStart && timeEnd) {
          description += ` ${timeStart}-${timeEnd}`;
        }
        if (isCancelled) {
          description += ' (отмена, оплачивается)';
        }

        const lessonResult = await pool.query(
          `INSERT INTO lessons (student_id, lesson_date, lesson_time, price, notes, created_by)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING *`,
          [studentId, report_date, lessonTime, price, notes || null, userId]
        );

        const lesson = lessonResult.rows[0];

        await pool.query(
          `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
           VALUES ($1, $2, 'lesson', $3, $4, $5)`,
          [
            studentId,
            price,
            description,
            lesson.id,
            userId
          ]
        );

        await pool.query(
          `INSERT INTO report_lessons (report_id, lesson_id)
           VALUES ($1, $2)`,
          [report.id, lesson.id]
        );

        createdLessons.push({ ...lesson, student_name: studentName });
      }
    }

    report.lessons = createdLessons;
    report.parsed_count = parsedLessons.length;
    report.created_count = createdLessons.length;

    res.json(report);
  } catch (error) {
    console.error('Ошибка обновления отчета:', error);
    res.status(500).json({ message: 'Ошибка обновления отчета' });
  }
};

// Удаление отчета
export const deleteReport = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { id } = req.params;

    // Проверяем, что отчет принадлежит пользователю
    const checkResult = await pool.query(
      'SELECT id FROM reports WHERE id = $1 AND created_by = $2',
      [id, userId]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Отчет не найден' });
    }

    // Получаем занятия из отчета
    const lessonsResult = await pool.query(
      `SELECT lesson_id FROM report_lessons WHERE report_id = $1`,
      [id]
    );

    // Удаляем транзакции и занятия
    for (const row of lessonsResult.rows) {
      await pool.query('DELETE FROM transactions WHERE lesson_id = $1', [row.lesson_id]);
      await pool.query('DELETE FROM lessons WHERE id = $1', [row.lesson_id]);
    }

    // Удаляем отчет (каскадно удалит связи)
    await pool.query('DELETE FROM reports WHERE id = $1', [id]);

    res.json({ message: 'Отчет удален' });
  } catch (error) {
    console.error('Ошибка удаления отчета:', error);
    res.status(500).json({ message: 'Ошибка удаления отчета' });
  }
};

