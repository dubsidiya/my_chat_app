import pool from '../db.js';
import {
  beginIdempotent,
  completeIdempotent,
  getIdempotencyKey,
  hashIdempotencyPayload,
} from '../utils/idempotency.js';
import { logAccountingEvent } from '../utils/accountingAudit.js';

// Пополнение баланса
export const depositBalance = async (req, res) => {
  const userId = req.user.userId;
  const student_id = parseInt(req.params.studentId);
  const { amount, description } = req.body;
  const idempotencyKey = getIdempotencyKey(req);

  // Преобразуем amount в число, если это строка
  const amountNum = typeof amount === 'string' ? parseFloat(amount) : amount;

  if (!student_id || isNaN(student_id) || !amountNum || amountNum <= 0) {
    return res.status(400).json({ message: 'ID студента и сумма обязательны' });
  }

  const client = await pool.connect();
  try {
    try { await client.query('ROLLBACK'); } catch (_) {}
    await client.query('BEGIN');
    const idem = await beginIdempotent(client, {
      userId,
      scope: 'transactions:deposit',
      key: idempotencyKey,
      requestHash: hashIdempotencyPayload({
        student_id,
        amount: amountNum,
        description: description || null,
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

    // Маршрут защищен requireSuperuser, поэтому пополнение возможно для любого существующего ученика.
    const exists = await client.query(
      'SELECT 1 FROM students WHERE id = $1 LIMIT 1',
      [student_id]
    );
    if (exists.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Студент не найден' });
    }

    // Создаем транзакцию пополнения (ручное пополнение - наличка)
    const finalDescription = description || 'Пополнение баланса (наличные)';
    const result = await client.query(
      `INSERT INTO transactions (student_id, amount, type, description, created_by)
       VALUES ($1, $2, 'deposit', $3, $4)
       RETURNING *`,
      [student_id, amountNum, finalDescription, userId]
    );
    const createdTx = result.rows[0];
    await completeIdempotent(client, {
      userId,
      scope: 'transactions:deposit',
      key: idempotencyKey,
      responseStatus: 201,
      responseBody: createdTx,
    });
    await logAccountingEvent({
      userId,
      eventType: 'deposit_created',
      entityType: 'transaction',
      entityId: createdTx.id,
      payload: {
        studentId: student_id,
        amount: amountNum,
      },
    });
    await client.query('COMMIT');
    res.status(201).json(createdTx);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка пополнения баланса:', error);
    res.status(500).json({ message: 'Ошибка пополнения баланса' });
  } finally {
    try { await client.query('ROLLBACK'); } catch (_) {}
    client.release();
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
    await logAccountingEvent({
      userId,
      eventType: 'deposit_deleted',
      entityType: 'transaction',
      entityId: id,
      payload: {},
    });

    return res.json({ message: 'Транзакция отменена', id });
  } catch (error) {
    console.error('Ошибка удаления транзакции:', error);
    return res.status(500).json({ message: 'Ошибка удаления транзакции' });
  }
};

