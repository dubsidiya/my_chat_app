import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';

const hasStudentAccess = async (client, teacherId, studentId) => {
  const r = await client.query(
    'SELECT 1 FROM teacher_students WHERE teacher_id = $1 AND student_id = $2 LIMIT 1',
    [teacherId, studentId]
  );
  return r.rows.length > 0;
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
    const result = onlyMine
        ? await pool.query(
            `SELECT * FROM lessons
             WHERE student_id = $1 AND created_by = $2
             ORDER BY lesson_date DESC, lesson_time DESC`,
            [studentId, userId]
          )
        : await pool.query(
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
  const userId = req.user.userId;
  const student_id = parseInt(req.params.studentId, 10);
  const { lesson_date, lesson_time, duration_minutes, price, notes } = req.body;

  // Преобразуем price в число, если это строка
  const priceNum = typeof price === 'string' ? parseFloat(price) : price;

  if (!student_id || isNaN(student_id) || !lesson_date || !priceNum || priceNum <= 0) {
    return res.status(400).json({ message: 'ID студента, дата и цена обязательны' });
  }

  // Создание урока + транзакции должно быть атомарным
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Проверяем, что студент доступен пользователю
    const can = await hasStudentAccess(client, userId, student_id);
    if (!can) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Студент не найден' });
    }

    // Защита от дубля: тот же студент, дата, время (или NULL) у того же владельца
    const lessonTimeValue = lesson_time || null;
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

    // Создаем занятие
    const lessonResult = await client.query(
      `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, notes, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [student_id, lesson_date, lessonTimeValue, duration_minutes || 60, priceNum, notes || null, userId]
    );

    const lesson = lessonResult.rows[0];

    // Создаем транзакцию списания
    await client.query(
      `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
       VALUES ($1, $2, 'lesson', $3, $4, $5)`,
      [
        student_id,
        priceNum,
        `Занятие ${lesson_date}${lesson_time ? ' в ' + lesson_time : ''}`,
        lesson.id,
        userId,
      ]
    );

    await client.query('COMMIT');
    return res.status(201).json(lesson);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка создания занятия:', error);
    return res.status(500).json({ message: 'Ошибка создания занятия' });
  } finally {
    client.release();
  }
};

// Удаление занятия
export const deleteLesson = async (req, res) => {
  const userId = req.user.userId;
  const { id } = req.params;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Проверяем, что занятие существует и принадлежит пользователю
    const checkResult = await client.query(
      `SELECT id FROM lessons WHERE id = $1 AND created_by = $2`,
      [id, userId]
    );

    if (checkResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Занятие не найдено' });
    }

    // Удаляем транзакции, связанные с занятием (только свои)
    await client.query(
      'DELETE FROM transactions WHERE lesson_id = $1 AND created_by = $2',
      [id, userId]
    );

    // Удаляем занятие
    await client.query('DELETE FROM lessons WHERE id = $1 AND created_by = $2', [id, userId]);

    await client.query('COMMIT');
    return res.json({ message: 'Занятие удалено' });
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка удаления занятия:', error);
    return res.status(500).json({ message: 'Ошибка удаления занятия' });
  } finally {
    client.release();
  }
};

