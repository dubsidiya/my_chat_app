import pool from '../db.js';

// Получение всех занятий студента
export const getStudentLessons = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { studentId } = req.params;

    // Проверяем, что студент принадлежит пользователю
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1 AND created_by = $2',
      [studentId, userId]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    const result = await pool.query(
      `SELECT * FROM lessons
       WHERE student_id = $1
       ORDER BY lesson_date DESC, lesson_time DESC`,
      [studentId]
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Ошибка получения занятий:', error);
    res.status(500).json({ message: 'Ошибка получения занятий' });
  }
};

// Создание занятия
export const createLesson = async (req, res) => {
  try {
    const userId = req.user.userId;
    const student_id = parseInt(req.params.studentId);
    const { lesson_date, lesson_time, duration_minutes, price, notes } = req.body;

    // Преобразуем price в число, если это строка
    const priceNum = typeof price === 'string' ? parseFloat(price) : price;

    if (!student_id || isNaN(student_id) || !lesson_date || !priceNum || priceNum <= 0) {
      return res.status(400).json({ message: 'ID студента, дата и цена обязательны' });
    }

    // Проверяем, что студент принадлежит пользователю
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1 AND created_by = $2',
      [student_id, userId]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    // Создаем занятие
    const lessonResult = await pool.query(
      `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, notes, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [student_id, lesson_date, lesson_time || null, duration_minutes || 60, priceNum, notes || null, userId]
    );

    const lesson = lessonResult.rows[0];

    // Создаем транзакцию списания
    await pool.query(
      `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
       VALUES ($1, $2, 'lesson', $3, $4, $5)`,
      [
        student_id,
        priceNum,
        `Занятие ${lesson_date}${lesson_time ? ' в ' + lesson_time : ''}`,
        lesson.id,
        userId
      ]
    );

    res.status(201).json(lesson);
  } catch (error) {
    console.error('Ошибка создания занятия:', error);
    res.status(500).json({ message: 'Ошибка создания занятия' });
  }
};

// Удаление занятия
export const deleteLesson = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { id } = req.params;

    // Проверяем, что занятие принадлежит пользователю
    const checkResult = await pool.query(
      `SELECT l.id, l.student_id FROM lessons l
       JOIN students s ON l.student_id = s.id
       WHERE l.id = $1 AND s.created_by = $2`,
      [id, userId]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Занятие не найдено' });
    }

    const lesson = checkResult.rows[0];

    // Удаляем транзакцию, связанную с занятием
    await pool.query(
      'DELETE FROM transactions WHERE lesson_id = $1',
      [id]
    );

    // Удаляем занятие
    await pool.query('DELETE FROM lessons WHERE id = $1', [id]);

    res.json({ message: 'Занятие удалено' });
  } catch (error) {
    console.error('Ошибка удаления занятия:', error);
    res.status(500).json({ message: 'Ошибка удаления занятия' });
  }
};

