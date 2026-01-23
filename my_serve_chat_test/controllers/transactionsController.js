import pool from '../db.js';

const hasStudentAccess = async (teacherId, studentId) => {
  const r = await pool.query(
    'SELECT 1 FROM teacher_students WHERE teacher_id = $1 AND student_id = $2 LIMIT 1',
    [teacherId, studentId]
  );
  return r.rows.length > 0;
};

// Пополнение баланса
export const depositBalance = async (req, res) => {
  try {
    const userId = req.user.userId;
    const student_id = parseInt(req.params.studentId);
    const { amount, description } = req.body;

    // Преобразуем amount в число, если это строка
    const amountNum = typeof amount === 'string' ? parseFloat(amount) : amount;

    if (!student_id || isNaN(student_id) || !amountNum || amountNum <= 0) {
      return res.status(400).json({ message: 'ID студента и сумма обязательны' });
    }

    // Проверяем, что студент доступен пользователю
    const can = await hasStudentAccess(userId, student_id);
    if (!can) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    // Создаем транзакцию пополнения (ручное пополнение - наличка)
    const finalDescription = description || 'Пополнение баланса (наличные)';
    const result = await pool.query(
      `INSERT INTO transactions (student_id, amount, type, description, created_by)
       VALUES ($1, $2, 'deposit', $3, $4)
       RETURNING *`,
      [student_id, amountNum, finalDescription, userId]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Ошибка пополнения баланса:', error);
    res.status(500).json({ message: 'Ошибка пополнения баланса' });
  }
};

