import pool from '../db.js';

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

    // Маршрут защищен requireSuperuser, поэтому пополнение возможно для любого существующего ученика.
    const exists = await pool.query(
      'SELECT 1 FROM students WHERE id = $1 LIMIT 1',
      [student_id]
    );
    if (exists.rows.length === 0) {
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

// Удаление транзакции (для undo пополнения)
export const deleteTransaction = async (req, res) => {
  try {
    const userId = req.user.userId;
    const id = parseInt(req.params.id, 10);
    if (!id || Number.isNaN(id)) {
      return res.status(400).json({ message: 'Некорректный ID транзакции' });
    }

    const txRes = await pool.query(
      `SELECT id, type, created_by
       FROM transactions
       WHERE id = $1
       LIMIT 1`,
      [id]
    );

    if (txRes.rows.length === 0) {
      return res.status(404).json({ message: 'Транзакция не найдена' });
    }

    const tx = txRes.rows[0];
    if (tx.type !== 'deposit') {
      return res.status(400).json({ message: 'Можно отменять только пополнения' });
    }

    // Для безопасности: отменять можно только свои пополнения
    if (tx.created_by !== userId) {
      return res.status(403).json({ message: 'Можно отменить только свои операции' });
    }

    const delRes = await pool.query(
      `DELETE FROM transactions
       WHERE id = $1 AND created_by = $2 AND type = 'deposit'
       RETURNING id`,
      [id, userId]
    );

    if (delRes.rows.length === 0) {
      return res.status(404).json({ message: 'Транзакция не найдена' });
    }

    return res.json({ message: 'Транзакция отменена', id });
  } catch (error) {
    console.error('Ошибка удаления транзакции:', error);
    return res.status(500).json({ message: 'Ошибка удаления транзакции' });
  }
};

