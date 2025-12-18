import pool from '../db.js';

// Получение всех студентов
export const getAllStudents = async (req, res) => {
  try {
    const userId = req.user.userId;
    
    const result = await pool.query(
      `SELECT s.*, 
              COALESCE(SUM(CASE WHEN t.type = 'deposit' THEN t.amount ELSE -t.amount END), 0) as balance
       FROM students s
       LEFT JOIN transactions t ON s.id = t.student_id
       WHERE s.created_by = $1
       GROUP BY s.id
       ORDER BY s.name`,
      [userId]
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Ошибка получения студентов:', error);
    res.status(500).json({ message: 'Ошибка получения списка студентов' });
  }
};

// Создание нового студента
export const createStudent = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { name, parent_name, phone, email, notes } = req.body;

    if (!name || name.trim() === '') {
      return res.status(400).json({ message: 'Имя студента обязательно' });
    }

    const result = await pool.query(
      `INSERT INTO students (name, parent_name, phone, email, notes, created_by)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [name.trim(), parent_name?.trim() || null, phone?.trim() || null, email?.trim() || null, notes?.trim() || null, userId]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Ошибка создания студента:', error);
    res.status(500).json({ message: 'Ошибка создания студента' });
  }
};

// Обновление студента
export const updateStudent = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { id } = req.params;
    const { name, parent_name, phone, email, notes } = req.body;

    // Проверяем, что студент принадлежит пользователю
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1 AND created_by = $2',
      [id, userId]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    const result = await pool.query(
      `UPDATE students 
       SET name = $1, parent_name = $2, phone = $3, email = $4, notes = $5, updated_at = CURRENT_TIMESTAMP
       WHERE id = $6 AND created_by = $7
       RETURNING *`,
      [name.trim(), parent_name?.trim() || null, phone?.trim() || null, email?.trim() || null, notes?.trim() || null, id, userId]
    );

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Ошибка обновления студента:', error);
    res.status(500).json({ message: 'Ошибка обновления студента' });
  }
};

// Удаление студента
export const deleteStudent = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { id } = req.params;

    // Проверяем, что студент принадлежит пользователю
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1 AND created_by = $2',
      [id, userId]
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
    const userId = req.user.userId;
    const { id } = req.params;

    // Проверяем, что студент принадлежит пользователю
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1 AND created_by = $2',
      [id, userId]
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
    const userId = req.user.userId;
    const { id } = req.params;

    // Проверяем, что студент принадлежит пользователю
    const checkResult = await pool.query(
      'SELECT id FROM students WHERE id = $1 AND created_by = $2',
      [id, userId]
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

