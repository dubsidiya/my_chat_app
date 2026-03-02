import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';
import { logAccountingEvent } from '../utils/accountingAudit.js';
import {
  beginIdempotent,
  completeIdempotent,
  getIdempotencyKey,
  hashIdempotencyPayload,
} from '../utils/idempotency.js';

const normalizePhoneDigits = (v) => (v || '').toString().replace(/\D/g, '');
const normalizeEmail = (v) => (v || '').toString().trim().toLowerCase();
const normalizeText = (v) =>
  (v || '')
    .toString()
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/[^a-zа-я0-9\s]/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();

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
       LEFT JOIN transactions t ON s.id = t.student_id AND t.created_by = $1
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
  const idempotencyKey = getIdempotencyKey(req);

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
    const idem = await beginIdempotent(client, {
      userId,
      scope: 'students:create',
      key: idempotencyKey,
      requestHash: hashIdempotencyPayload({
        name: trimmedName,
        parent_name: parent_name || null,
        phone: trimmedPhone,
        email: normalizedEmail,
        notes: notes || null,
        pay_by_bank_transfer: payByBank,
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

      await logAccountingEvent({
        client,
        userId,
        eventType: 'student_linked_existing',
        entityType: 'student',
        entityId: student.id,
        payload: {
          wasExisting: true,
        },
      });
      await completeIdempotent(client, {
        userId,
        scope: 'students:create',
        key: idempotencyKey,
        responseStatus: 200,
        responseBody: student,
      });

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
    await logAccountingEvent({
      client,
      userId,
      eventType: 'student_created',
      entityType: 'student',
      entityId: student.id,
      payload: {
        payByBankTransfer: payByBank,
      },
    });
    await completeIdempotent(client, {
      userId,
      scope: 'students:create',
      key: idempotencyKey,
      responseStatus: 201,
      responseBody: student,
    });

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

// Поиск похожих учеников по имени/фамилии, чтобы не создавать дубли из-за опечаток.
export const searchStudentSuggestions = async (req, res) => {
  try {
    const userId = req.user.userId;
    const query = (req.query.q || '').toString().trim();
    const limitRaw = parseInt((req.query.limit || '8').toString(), 10);
    const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(limitRaw, 20)) : 8;

    if (query.length < 2) {
      return res.json([]);
    }

    const normalizedQuery = normalizeText(query);
    const likePattern = `%${normalizedQuery.replace(/\s+/g, '%')}%`;
    let result;
    try {
      result = await pool.query(
        `WITH q AS (
           SELECT LOWER(REPLACE($2::text, 'ё', 'е')) AS needle
         )
         SELECT
           s.id,
           s.name,
           s.parent_name,
           s.phone,
           s.email,
           s.pay_by_bank_transfer,
           CASE WHEN ts.teacher_id IS NULL THEN FALSE ELSE TRUE END AS is_linked,
           GREATEST(
             similarity(LOWER(REPLACE(TRIM(s.name), 'ё', 'е')), (SELECT needle FROM q)),
             similarity(LOWER(REPLACE(TRIM(COALESCE(s.parent_name, '')), 'ё', 'е')), (SELECT needle FROM q)) * 0.75
           ) AS score
         FROM students s
         LEFT JOIN teacher_students ts ON ts.student_id = s.id AND ts.teacher_id = $1
         WHERE
           LOWER(REPLACE(TRIM(s.name), 'ё', 'е')) % (SELECT needle FROM q)
           OR LOWER(REPLACE(TRIM(s.name), 'ё', 'е')) LIKE $3
           OR LOWER(REPLACE(TRIM(COALESCE(s.parent_name, '')), 'ё', 'е')) LIKE $3
         ORDER BY is_linked DESC, score DESC, s.name ASC
         LIMIT $4`,
        [userId, normalizedQuery, likePattern, limit]
      );
    } catch (trgmError) {
      // Fallback, если расширение pg_trgm ещё не применено.
      result = await pool.query(
        `SELECT
           s.id,
           s.name,
           s.parent_name,
           s.phone,
           s.email,
           s.pay_by_bank_transfer,
           CASE WHEN ts.teacher_id IS NULL THEN FALSE ELSE TRUE END AS is_linked
         FROM students s
         LEFT JOIN teacher_students ts ON ts.student_id = s.id AND ts.teacher_id = $1
         WHERE
           LOWER(REPLACE(TRIM(s.name), 'ё', 'е')) LIKE $2
           OR LOWER(REPLACE(TRIM(COALESCE(s.parent_name, '')), 'ё', 'е')) LIKE $2
         ORDER BY is_linked DESC, s.name ASC
         LIMIT $3`,
        [userId, likePattern, limit]
      );
    }

    return res.json(
      result.rows.map((row) => ({
        id: row.id,
        name: row.name,
        parent_name: row.parent_name,
        phone: row.phone,
        email: row.email,
        pay_by_bank_transfer: row.pay_by_bank_transfer === true,
        is_linked: row.is_linked === true,
      }))
    );
  } catch (error) {
    console.error('Ошибка поиска похожих учеников:', error);
    return res.status(500).json({ message: 'Ошибка поиска учеников' });
  }
};

// Явная привязка существующего ученика к преподавателю.
export const linkExistingStudent = async (req, res) => {
  const userId = req.user.userId;
  const studentId = parseInt(req.body?.student_id, 10);
  const idempotencyKey = getIdempotencyKey(req);
  if (!studentId || Number.isNaN(studentId)) {
    return res.status(400).json({ message: 'Некорректный student_id' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const idem = await beginIdempotent(client, {
      userId,
      scope: 'students:link-existing',
      key: idempotencyKey,
      requestHash: hashIdempotencyPayload({ studentId }),
    });
    if (idem.replay) {
      await client.query('ROLLBACK');
      return res.status(idem.responseStatus).json(idem.responseBody);
    }
    if (idem.conflict) {
      await client.query('ROLLBACK');
      return res.status(409).json({ message: idem.conflict });
    }
    const existing = await client.query(
      'SELECT * FROM students WHERE id = $1 LIMIT 1',
      [studentId]
    );
    if (existing.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Студент не найден' });
    }

    await ensureTeacherStudentLink(client, userId, studentId);
    await logAccountingEvent({
      client,
      userId,
      eventType: 'student_linked_manual',
      entityType: 'student',
      entityId: studentId,
      payload: {},
    });
    await completeIdempotent(client, {
      userId,
      scope: 'students:link-existing',
      key: idempotencyKey,
      responseStatus: 200,
      responseBody: existing.rows[0],
    });
    await client.query('COMMIT');
    return res.status(200).json(existing.rows[0]);
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка привязки существующего ученика:', error);
    return res.status(500).json({ message: 'Ошибка привязки ученика' });
  } finally {
    client.release();
  }
};

// Обновление студента (владелец по teacher_students или суперпользователь — любого)
export const updateStudent = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { id } = req.params;
    const { name, parent_name, phone, email, notes, pay_by_bank_transfer } = req.body;
    const payByBank = pay_by_bank_transfer === true || pay_by_bank_transfer === 'true';

    if (!name || !name.toString().trim()) {
      return res.status(400).json({ message: 'Имя студента обязательно' });
    }

    // Суперпользователь может править любого; иначе — только при наличии связи teacher_students
    if (!isSuperuser(req.user)) {
      const checkResult = await pool.query(
        'SELECT 1 FROM teacher_students WHERE teacher_id = $1 AND student_id = $2 LIMIT 1',
        [userId, id]
      );
      if (checkResult.rows.length === 0) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
    } else {
      // Суперпользователь: проверяем, что студент вообще есть в базе
      const exists = await pool.query('SELECT 1 FROM students WHERE id = $1 LIMIT 1', [id]);
      if (exists.rows.length === 0) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
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

// Удаление студента из списка преподавателя (и удаление из БД, если больше ни у кого не привязан).
// Суперпользователь может удалить любого ученика (в т.ч. без своей связи в teacher_students).
export const deleteStudent = async (req, res) => {
  const userId = req.user.userId;
  const { id } = req.params;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const isSuper = isSuperuser(req.user);
    const hasAccess = isSuper || (await assertTeacherHasStudentAccess(client, userId, id));
    if (!hasAccess) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Студент не найден' });
    }

    if (isSuper) {
      // Суперпользователь: проверяем существование и удаляем студента полностью
      const studentExists = await client.query('SELECT 1 FROM students WHERE id = $1 LIMIT 1', [id]);
      if (studentExists.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ message: 'Студент не найден' });
      }
      await client.query('DELETE FROM teacher_students WHERE student_id = $1', [id]);
      await client.query('DELETE FROM students WHERE id = $1', [id]);
      await logAccountingEvent({
        client,
        userId,
        eventType: 'student_deleted_full',
        entityType: 'student',
        entityId: id,
        payload: { bySuperuser: true },
      });
    } else {
      // Обычный преподаватель: снимаем только свою привязку
      await client.query(
        'DELETE FROM teacher_students WHERE teacher_id = $1 AND student_id = $2',
        [userId, id]
      );
      const stillLinked = await client.query(
        'SELECT 1 FROM teacher_students WHERE student_id = $1 LIMIT 1',
        [id]
      );
      if (stillLinked.rows.length === 0) {
        await client.query('DELETE FROM students WHERE id = $1', [id]);
        await logAccountingEvent({
          client,
          userId,
          eventType: 'student_deleted_full',
          entityType: 'student',
          entityId: id,
          payload: { bySuperuser: false },
        });
      } else {
        await logAccountingEvent({
          client,
          userId,
          eventType: 'student_unlinked',
          entityType: 'student',
          entityId: id,
          payload: {},
        });
      }
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
    const mine = req.query.mine === '1' || req.query.mine === 'true';

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

    const result = mine
      ? await pool.query(
          `SELECT COALESCE(SUM(CASE WHEN type IN ('deposit', 'refund') THEN amount ELSE -amount END), 0) as balance
           FROM transactions
           WHERE student_id = $1 AND created_by = $2`,
          [id, userId]
        )
      : await pool.query(
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
    const mine = req.query.mine === '1' || req.query.mine === 'true';

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

    const result = mine
      ? await pool.query(
          `SELECT t.*, l.lesson_date, l.lesson_time, u.email as teacher_username
           FROM transactions t
           LEFT JOIN lessons l ON t.lesson_id = l.id
           LEFT JOIN users u ON t.created_by = u.id
           WHERE t.student_id = $1 AND t.created_by = $2
           ORDER BY t.created_at DESC`,
          [id, userId]
        )
      : await pool.query(
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

