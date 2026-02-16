import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';

const normalizePhoneDigits = (v) => (v || '').toString().replace(/\D/g, '');
const normalizeEmail = (v) => (v || '').toString().trim().toLowerCase();

const ensureTeacherStudentLink = async (client, teacherId, studentId) => {
  await client.query(
    `INSERT INTO teacher_students (teacher_id, student_id)
     VALUES ($1, $2)
     ON CONFLICT DO NOTHING`,
    [teacherId, studentId]
  );
};

const assertTeacherHasStudentAccess = async (client, teacherId, studentId) => {
  const r = await client.query(
    `SELECT 1
     FROM teacher_students
     WHERE teacher_id = $1 AND student_id = $2
     LIMIT 1`,
    [teacherId, studentId]
  );
  return r.rows.length > 0;
};

// Получение всех студентов (привязаны к владельцу created_by)
export const getAllStudents = async (req, res) => {
  try {
    // Суперпользователь (бухгалтерия) должен видеть всех учеников
    if (isSuperuser(req.user)) {
      const result = await pool.query(
        `SELECT s.*, 
                COALESCE(SUM(CASE WHEN t.type IN ('deposit', 'refund') THEN t.amount ELSE -t.amount END), 0) as balance
         FROM students s
         LEFT JOIN transactions t ON s.id = t.student_id
         GROUP BY s.id
         ORDER BY s.name`
      );
      return res.json(result.rows);
    }

    const userId = req.user.userId;
    const result = await pool.query(
      `SELECT s.*, 
              COALESCE(SUM(CASE WHEN t.type IN ('deposit', 'refund') THEN t.amount ELSE -t.amount END), 0) as balance
       FROM teacher_students ts
       JOIN students s ON s.id = ts.student_id
       LEFT JOIN transactions t ON s.id = t.student_id
       WHERE ts.teacher_id = $1
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

// Создание нового студента (или возврат существующего, если уже есть)
export const createStudent = async (req, res) => {
  const userId = req.user.userId;
  const { name, parent_name, phone, email, notes, pay_by_bank_transfer } = req.body;
  const payByBank = pay_by_bank_transfer === true || pay_by_bank_transfer === 'true';

  if (!name || name.trim() === '') {
    return res.status(400).json({ message: 'Имя студента обязательно' });
  }

  const trimmedName = name.trim();
  const trimmedPhone = phone?.trim() || null;
  const phoneDigits = normalizePhoneDigits(trimmedPhone);
  const normalizedEmail = email ? normalizeEmail(email) : null;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Ищем существующего студента в общем реестре:
    // 1) по телефону (если есть), 2) по email (если есть).
    // Важно: если нет ни телефона, ни email — НЕ объединяем по одному только имени (чтобы не склеить разных детей с одинаковыми именами).
    let existingStudent = null;

    if (phoneDigits) {
      const r = await client.query(
        `SELECT *
         FROM students
         WHERE regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') = $1
         LIMIT 1`,
        [phoneDigits]
      );
      if (r.rows.length > 0) existingStudent = r.rows[0];
    }

    if (!existingStudent && normalizedEmail) {
      const r = await client.query(
        `SELECT *
         FROM students
         WHERE LOWER(TRIM(COALESCE(email, ''))) = $1
         LIMIT 1`,
        [normalizedEmail]
      );
      if (r.rows.length > 0) existingStudent = r.rows[0];
    }

    // Если нет ни телефона, ни email — пробуем объединить по имени,
    // но ТОЛЬКО если в базе ровно один кандидат (чтобы не склеить однофамильцев).
    if (!existingStudent && !phoneDigits && !normalizedEmail) {
      const r = await client.query(
        `SELECT *
         FROM students
         WHERE LOWER(TRIM(name)) = LOWER($1)`,
        [trimmedName]
      );
      if (r.rows.length === 1) {
        existingStudent = r.rows[0];
      }
    }

    if (existingStudent) {
      // Привязываем студента текущему преподавателю (если ещё не привязан)
      await ensureTeacherStudentLink(client, userId, existingStudent.id);

      // Заполняем недостающие поля, не перетирая существующие
      const updates = [];
      const values = [];
      let idx = 1;

      if (parent_name && parent_name.trim() && !existingStudent.parent_name) {
        updates.push(`parent_name = $${idx++}`);
        values.push(parent_name.trim());
      }
      if (trimmedPhone && !existingStudent.phone) {
        updates.push(`phone = $${idx++}`);
        values.push(trimmedPhone);
      }
      if (normalizedEmail && !existingStudent.email) {
        updates.push(`email = $${idx++}`);
        values.push(normalizedEmail);
      }
      if (notes && notes.trim() && !existingStudent.notes) {
        updates.push(`notes = $${idx++}`);
        values.push(notes.trim());
      }
      if (existingStudent.pay_by_bank_transfer !== payByBank) {
        updates.push(`pay_by_bank_transfer = $${idx++}`);
        values.push(payByBank);
      }

      let student = existingStudent;
      if (updates.length > 0) {
        values.push(existingStudent.id);
        const upd = await client.query(
          `UPDATE students
           SET ${updates.join(', ')}, updated_at = CURRENT_TIMESTAMP
           WHERE id = $${idx}
           RETURNING *`,
          values
        );
        student = upd.rows[0];
      }

      await client.query('COMMIT');
      return res.status(200).json(student);
    }

    // Создаем нового студента и сразу привязываем к преподавателю
    const created = await client.query(
      `INSERT INTO students (name, parent_name, phone, email, notes, pay_by_bank_transfer, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [
        trimmedName,
        parent_name?.trim() || null,
        trimmedPhone,
        normalizedEmail,
        notes?.trim() || null,
        payByBank,
        userId,
      ]
    );
    const student = created.rows[0];
    await ensureTeacherStudentLink(client, userId, student.id);

    await client.query('COMMIT');
    return res.status(201).json(student);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка создания студента:', error);
    return res.status(500).json({ message: 'Ошибка создания студента' });
  } finally {
    client.release();
  }
};

// Обновление студента (только владелец)
export const updateStudent = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { id } = req.params;
    const { name, parent_name, phone, email, notes, pay_by_bank_transfer } = req.body;
    const payByBank = pay_by_bank_transfer === true || pay_by_bank_transfer === 'true';

    if (!name || !name.toString().trim()) {
      return res.status(400).json({ message: 'Имя студента обязательно' });
    }

    // Проверяем доступ к студенту через связь teacher_students
    const checkResult = await pool.query(
      'SELECT 1 FROM teacher_students WHERE teacher_id = $1 AND student_id = $2 LIMIT 1',
      [userId, id]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    const result = await pool.query(
      `UPDATE students 
       SET name = $1, parent_name = $2, phone = $3, email = $4, notes = $5, pay_by_bank_transfer = $6, updated_at = CURRENT_TIMESTAMP
       WHERE id = $7
       RETURNING *`,
      [
        name.toString().trim(),
        parent_name?.trim() || null,
        phone?.trim() || null,
        email ? normalizeEmail(email) : null,
        notes?.trim() || null,
        payByBank,
        id,
      ]
    );

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Ошибка обновления студента:', error);
    res.status(500).json({ message: 'Ошибка обновления студента' });
  }
};

// Удаление студента из списка преподавателя (и удаление из БД, если больше ни у кого не привязан)
export const deleteStudent = async (req, res) => {
  const userId = req.user.userId;
  const { id } = req.params;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const hasAccess = await assertTeacherHasStudentAccess(client, userId, id);
    if (!hasAccess) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Студент не найден' });
    }

    // Снимаем привязку студент↔преподаватель
    await client.query(
      'DELETE FROM teacher_students WHERE teacher_id = $1 AND student_id = $2',
      [userId, id]
    );

    // Если больше ни у кого не числится — удаляем полностью
    const stillLinked = await client.query(
      'SELECT 1 FROM teacher_students WHERE student_id = $1 LIMIT 1',
      [id]
    );
    if (stillLinked.rows.length === 0) {
      await client.query('DELETE FROM students WHERE id = $1', [id]);
    }

    await client.query('COMMIT');
    return res.json({ message: 'Студент удален' });
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка удаления студента:', error);
    return res.status(500).json({ message: 'Ошибка удаления студента' });
  } finally {
    client.release();
  }
};

// Получение баланса студента
export const getStudentBalance = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { id } = req.params;

    // Суперпользователь (бухгалтерия) может смотреть баланс любого ученика
    if (!isSuperuser(req.user)) {
      const checkResult = await pool.query(
        'SELECT 1 FROM teacher_students WHERE teacher_id = $1 AND student_id = $2 LIMIT 1',
        [userId, id]
      );
      if (checkResult.rows.length === 0) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
    }

    const result = await pool.query(
      `SELECT COALESCE(SUM(CASE WHEN type IN ('deposit', 'refund') THEN amount ELSE -amount END), 0) as balance
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

    // Суперпользователь (бухгалтерия) может смотреть транзакции любого ученика
    if (!isSuperuser(req.user)) {
      const checkResult = await pool.query(
        'SELECT 1 FROM teacher_students WHERE teacher_id = $1 AND student_id = $2 LIMIT 1',
        [userId, id]
      );
      if (checkResult.rows.length === 0) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
    }

    const result = await pool.query(
      `SELECT t.*, l.lesson_date, l.lesson_time, u.email as teacher_username
       FROM transactions t
       LEFT JOIN lessons l ON t.lesson_id = l.id
       LEFT JOIN users u ON t.created_by = u.id
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

