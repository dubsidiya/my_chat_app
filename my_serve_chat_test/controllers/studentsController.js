import pool from '../db.js';

// Получение всех студентов (общие для всех преподавателей)
export const getAllStudents = async (req, res) => {
  try {
    // Убрали фильтрацию по created_by - все преподаватели видят всех студентов
    const result = await pool.query(
      `SELECT s.*, 
              COALESCE(SUM(CASE WHEN t.type = 'deposit' THEN t.amount ELSE -t.amount END), 0) as balance
       FROM students s
       LEFT JOIN transactions t ON s.id = t.student_id
       GROUP BY s.id
       ORDER BY s.name`
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Ошибка получения студентов:', error);
    res.status(500).json({ message: 'Ошибка получения списка студентов' });
  }
};

// Создание нового студента (или возврат существующего, если уже есть)
export const createStudent = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { name, parent_name, phone, email, notes } = req.body;

    if (!name || name.trim() === '') {
      return res.status(400).json({ message: 'Имя студента обязательно' });
    }

    const trimmedName = name.trim();
    const trimmedPhone = phone?.trim() || null;

    // Проверяем, существует ли уже студент с таким именем (и телефоном, если указан)
    // Если телефон указан, ищем по имени И телефону
    // Если телефона нет, ищем только по имени
    let existingStudent = null;
    if (trimmedPhone) {
      const existingResult = await pool.query(
        `SELECT * FROM students 
         WHERE LOWER(TRIM(name)) = LOWER($1) 
         AND (phone IS NULL OR phone = $2 OR phone = $3)`,
        [trimmedName, trimmedPhone, trimmedPhone.replace(/\D/g, '')]
      );
      if (existingResult.rows.length > 0) {
        existingStudent = existingResult.rows[0];
      }
    } else {
      // Если телефона нет, ищем только по имени (точное совпадение)
      const existingResult = await pool.query(
        `SELECT * FROM students 
         WHERE LOWER(TRIM(name)) = LOWER($1)`,
        [trimmedName]
      );
      if (existingResult.rows.length > 0) {
        existingStudent = existingResult.rows[0];
      }
    }

    // Если студент уже существует, возвращаем его
    if (existingStudent) {
      // Обновляем данные, если они были изменены (но не перезаписываем существующие данные)
      const updates = [];
      const values = [];
      let paramIndex = 1;

      if (parent_name && parent_name.trim() && !existingStudent.parent_name) {
        updates.push(`parent_name = $${paramIndex++}`);
        values.push(parent_name.trim());
      }
      if (trimmedPhone && !existingStudent.phone) {
        updates.push(`phone = $${paramIndex++}`);
        values.push(trimmedPhone);
      }
      if (email && email.trim() && !existingStudent.email) {
        updates.push(`email = $${paramIndex++}`);
        values.push(email.trim());
      }
      if (notes && notes.trim() && !existingStudent.notes) {
        updates.push(`notes = $${paramIndex++}`);
        values.push(notes.trim());
      }

      if (updates.length > 0) {
        values.push(existingStudent.id);
        const updateResult = await pool.query(
          `UPDATE students 
           SET ${updates.join(', ')}, updated_at = CURRENT_TIMESTAMP
           WHERE id = $${paramIndex}
           RETURNING *`,
          values
        );
        return res.status(200).json(updateResult.rows[0]);
      }

      return res.status(200).json(existingStudent);
    }

    // Если студента нет, создаем нового
    const result = await pool.query(
      `INSERT INTO students (name, parent_name, phone, email, notes, created_by)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [trimmedName, parent_name?.trim() || null, trimmedPhone, email?.trim() || null, notes?.trim() || null, userId]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Ошибка создания студента:', error);
    res.status(500).json({ message: 'Ошибка создания студента' });
  }
};

// Обновление студента (любой преподаватель может обновить)
export const updateStudent = async (req, res) => {
  try {
    const { id } = req.params;
    const { name, parent_name, phone, email, notes } = req.body;

    // Проверяем, что студент существует
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1',
      [id]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    const result = await pool.query(
      `UPDATE students 
       SET name = $1, parent_name = $2, phone = $3, email = $4, notes = $5, updated_at = CURRENT_TIMESTAMP
       WHERE id = $6
       RETURNING *`,
      [name.trim(), parent_name?.trim() || null, phone?.trim() || null, email?.trim() || null, notes?.trim() || null, id]
    );

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Ошибка обновления студента:', error);
    res.status(500).json({ message: 'Ошибка обновления студента' });
  }
};

// Удаление студента (любой преподаватель может удалить)
export const deleteStudent = async (req, res) => {
  try {
    const { id } = req.params;

    // Проверяем, что студент существует
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1',
      [id]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    await pool.query('DELETE FROM students WHERE id = $1', [id]);

    res.json({ message: 'Студент удален' });
  } catch (error) {
    console.error('Ошибка удаления студента:', error);
    res.status(500).json({ message: 'Ошибка удаления студента' });
  }
};

// Получение баланса студента
export const getStudentBalance = async (req, res) => {
  try {
    const { id } = req.params;

    // Проверяем, что студент существует
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1',
      [id]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    const result = await pool.query(
      `SELECT COALESCE(SUM(CASE WHEN type = 'deposit' THEN amount ELSE -amount END), 0) as balance
       FROM transactions
       WHERE student_id = $1`,
      [id]
    );

    res.json({ balance: parseFloat(result.rows[0].balance) });
  } catch (error) {
    console.error('Ошибка получения баланса:', error);
    res.status(500).json({ message: 'Ошибка получения баланса' });
  }
};

// Получение истории транзакций студента
export const getStudentTransactions = async (req, res) => {
  try {
    const { id } = req.params;

    // Проверяем, что студент существует
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1',
      [id]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    const result = await pool.query(
      `SELECT t.*, l.lesson_date, l.lesson_time
       FROM transactions t
       LEFT JOIN lessons l ON t.lesson_id = l.id
       WHERE t.student_id = $1
       ORDER BY t.created_at DESC`,
      [id]
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Ошибка получения транзакций:', error);
    res.status(500).json({ message: 'Ошибка получения истории транзакций' });
  }
};

