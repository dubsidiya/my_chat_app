import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';
import { logAccountingEvent } from '../utils/accountingAudit.js';
import { sqlUserAccountingNameOrEmpty } from '../utils/userAccountingDisplaySql.js';
import { parsePositiveInt } from '../utils/sanitize.js';
import {
  beginIdempotent,
  completeIdempotent,
  getIdempotencyKey,
  hashIdempotencyPayload,
} from '../utils/idempotency.js';
import { SQL_OPEN_MAKEUP_DEBT_ON_LESSON } from '../utils/makeupDebts.js';
import { sqlTeacherVisibleStudentBalance } from '../services/accounting/teacherStudentBalance.js';

const normalizePhoneDigits = (v) => (v || '').toString().replace(/\D/g, '');
const normalizeEmail = (v) => (v || '').toString().trim().toLowerCase();
const hasOwn = (obj, key) => Object.prototype.hasOwnProperty.call(obj || {}, key);
const parsePayByBankFlag = (value) => value === true || value === 'true';
const optionalTrimToNull = (value) => {
  if (value == null) return null;
  const s = String(value).trim();
  return s ? s : null;
};
const normalizeText = (v) =>
  (v || '')
    .toString()
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/[^a-zа-я0-9\s]/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();

// Максимум строк на страницу для списков (M17).
const LIST_MAX_LIMIT = 1000;

// M17: разбор необязательных limit/offset. При отсутствии параметров возвращаем
// { limit: null, offset: null } — поведение прежнее (все строки), клиент не ломается.
const parseLimitOffset = (req, maxLimit = LIST_MAX_LIMIT) => {
  const out = { limit: null, offset: null };
  const rawLimit = req.query?.limit;
  const rawOffset = req.query?.offset;
  if (rawLimit != null && String(rawLimit).trim() !== '') {
    const n = parseInt(String(rawLimit), 10);
    if (!Number.isInteger(n) || n < 1 || n > maxLimit) {
      return { error: `limit должен быть целым числом от 1 до ${maxLimit}` };
    }
    out.limit = n;
  }
  if (rawOffset != null && String(rawOffset).trim() !== '') {
    const n = parseInt(String(rawOffset), 10);
    if (!Number.isInteger(n) || n < 0) {
      return { error: 'offset должен быть неотрицательным целым числом' };
    }
    out.offset = n;
  }
  return out;
};

// Дописывает LIMIT/OFFSET к запросу и параметрам только при наличии значений.
const buildLimitOffsetSql = (params, { limit, offset }) => {
  let sql = '';
  if (limit != null) {
    params.push(limit);
    sql += ` LIMIT $${params.length}`;
  }
  if (offset != null) {
    params.push(offset);
    sql += ` OFFSET $${params.length}`;
  }
  return sql;
};

/** Явная привязка снова делает ученика активным (снимает выпускники). */
const ensureTeacherStudentLinkActive = async (client, teacherId, studentId) => {
  await client.query(
    `INSERT INTO teacher_students (teacher_id, student_id, is_archived, archived_at)
     VALUES ($1, $2, false, NULL)
     ON CONFLICT (teacher_id, student_id) DO UPDATE
       SET is_archived = false,
           archived_at = NULL`,
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
    const userId = req.user.userId;
    const pagination = parseLimitOffset(req); // M17 (необязательные limit/offset)
    if (pagination.error) {
      return res.status(400).json({ message: pagination.error });
    }

    // Суперпользователь (бухгалтерия) должен видеть всех учеников.
    // is_archived — только личный архив суперюзера (его строка в teacher_students), иначе false.
    if (isSuperuser(req.user)) {
      const params = [userId];
      const pageClause = buildLimitOffsetSql(params, pagination);
      const result = await pool.query(
        `SELECT s.*,
                COALESCE(BOOL_OR(ts.is_archived), false) AS is_archived,
                MAX(ts.archived_at) AS archived_at,
                COALESCE(SUM(CASE WHEN t.type IN ('deposit', 'refund') THEN t.amount ELSE -t.amount END), 0) as balance
         FROM students s
         LEFT JOIN teacher_students ts ON ts.student_id = s.id AND ts.teacher_id = $1
         LEFT JOIN transactions t ON s.id = t.student_id
         GROUP BY s.id
         ORDER BY s.name${pageClause}`,
        params
      );
      return res.json(result.rows);
    }

    const params = [userId];
    const pageClause = buildLimitOffsetSql(params, pagination);
    const result = await pool.query(
      `SELECT s.*,
              BOOL_OR(ts.is_archived) AS is_archived,
              MAX(ts.archived_at) AS archived_at,
              COALESCE((${sqlTeacherVisibleStudentBalance({ studentIdSql: 's.id', teacherIdSql: '$1' })}), 0) AS balance
       FROM teacher_students ts
       JOIN students s ON s.id = ts.student_id
       WHERE ts.teacher_id = $1
       GROUP BY s.id
       ORDER BY s.name${pageClause}`,
      params
    );

    res.json(result.rows);
  } catch (error) {
    console.error('Ошибка получения студентов:', error);
    res.status(500).json({ message: 'Ошибка получения списка студентов' });
  }
};

// Сводка «к отработке»: открытые долги (missed + cancel_same_day без привязанной makeup).
export const getMakeupPendingSummary = async (req, res) => {
  try {
    const userId = req.user.userId;
    // Super (бухгалтерия) — глобальная сводка по всем ученикам, как getAllStudents.
    // Обычный преподаватель — только свои связи teacher_students и свои занятия.
    const result = isSuperuser(req.user)
      ? await pool.query(
          `SELECT
             s.id AS student_id,
             s.name AS student_name,
             COUNT(*) FILTER (
               WHERE ${SQL_OPEN_MAKEUP_DEBT_ON_LESSON}
                 AND l.status = 'missed'
             )::int AS open_missed_count,
             COUNT(*) FILTER (
               WHERE ${SQL_OPEN_MAKEUP_DEBT_ON_LESSON}
                 AND l.status = 'cancel_same_day'
             )::int AS open_cancel_count,
             COUNT(*) FILTER (WHERE l.status = 'makeup')::int AS makeup_count
           FROM students s
           JOIN lessons l ON l.student_id = s.id
           GROUP BY s.id, s.name
           HAVING COUNT(*) FILTER (WHERE ${SQL_OPEN_MAKEUP_DEBT_ON_LESSON}) > 0
           ORDER BY COUNT(*) FILTER (WHERE ${SQL_OPEN_MAKEUP_DEBT_ON_LESSON}) DESC, s.name ASC`
        )
      : await pool.query(
          `SELECT
             s.id AS student_id,
             s.name AS student_name,
             COUNT(*) FILTER (
               WHERE ${SQL_OPEN_MAKEUP_DEBT_ON_LESSON}
                 AND l.status = 'missed'
             )::int AS open_missed_count,
             COUNT(*) FILTER (
               WHERE ${SQL_OPEN_MAKEUP_DEBT_ON_LESSON}
                 AND l.status = 'cancel_same_day'
             )::int AS open_cancel_count,
             COUNT(*) FILTER (WHERE l.status = 'makeup')::int AS makeup_count
           FROM teacher_students ts
           JOIN students s ON s.id = ts.student_id
           JOIN lessons l ON l.student_id = s.id AND l.created_by = $1
           WHERE ts.teacher_id = $1
           GROUP BY s.id, s.name
           HAVING COUNT(*) FILTER (WHERE ${SQL_OPEN_MAKEUP_DEBT_ON_LESSON}) > 0
           ORDER BY COUNT(*) FILTER (WHERE ${SQL_OPEN_MAKEUP_DEBT_ON_LESSON}) DESC, s.name ASC`,
          [userId]
        );

    const totalPending = result.rows.reduce(
      (acc, r) => acc + Number(r.open_missed_count || 0) + Number(r.open_cancel_count || 0),
      0
    );
    return res.json({
      totalPending,
      studentsCount: result.rows.length,
      items: result.rows.map((r) => {
        const openMissed = Number(r.open_missed_count || 0);
        const openCancel = Number(r.open_cancel_count || 0);
        return {
          studentId: r.student_id,
          studentName: r.student_name,
          openMissedCount: openMissed,
          openCancelCount: openCancel,
          missedCount: openMissed,
          makeupCount: Number(r.makeup_count || 0),
          pendingCount: openMissed + openCancel,
        };
      }),
    });
  } catch (error) {
    console.error('Ошибка получения сводки отработок:', error);
    return res.status(500).json({ message: 'Ошибка получения сводки отработок' });
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
    try { await client.query('ROLLBACK'); } catch (_) {}
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
      await ensureTeacherStudentLinkActive(client, userId, existingStudent.id);

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
    await ensureTeacherStudentLinkActive(client, userId, student.id);
    await logAccountingEvent({
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
    try { await client.query('ROLLBACK'); } catch (_) {}
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
      // M18/L10: фолбэк только для случаев, когда недоступен pg_trgm:
      //  42883 — оператор % не существует (расширение не создано);
      //  42P01 — отсутствует таблица/отношение.
      // Любую другую ошибку (сеть, права, таймаут) пробрасываем во внешний catch,
      // а не превращаем молча во второй LIKE-скан.
      if (trgmError?.code !== '42883' && trgmError?.code !== '42P01') {
        throw trgmError;
      }
      console.warn(
        'searchStudentSuggestions: pg_trgm недоступен, использую LIKE-фолбэк:',
        trgmError?.code,
        trgmError?.message
      );
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
    try { await client.query('ROLLBACK'); } catch (_) {}
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

    await ensureTeacherStudentLinkActive(client, userId, studentId);
    await logAccountingEvent({
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
    try { await client.query('ROLLBACK'); } catch (_) {}
    client.release();
  }
};

// Обновление студента (владелец по teacher_students или суперпользователь — любого)
export const updateStudent = async (req, res) => {
  try {
    const userId = req.user.userId;
    const studentId = parsePositiveInt(req.params.id);
    if (!studentId) {
      return res.status(400).json({ message: 'Некорректный ID ученика' });
    }
    const body = req.body || {};

    if (!isSuperuser(req.user)) {
      const checkResult = await pool.query(
        'SELECT 1 FROM teacher_students WHERE teacher_id = $1 AND student_id = $2 LIMIT 1',
        [userId, studentId]
      );
      if (checkResult.rows.length === 0) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
    } else {
      const exists = await pool.query('SELECT 1 FROM students WHERE id = $1 LIMIT 1', [studentId]);
      if (exists.rows.length === 0) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
    }

    const sets = [];
    const values = [];
    const addSet = (column, value) => {
      values.push(value);
      sets.push(`${column} = $${values.length}`);
    };

    if (hasOwn(body, 'name')) {
      const trimmedName = (body.name ?? '').toString().trim();
      if (!trimmedName) {
        return res.status(400).json({ message: 'Имя студента обязательно' });
      }
      addSet('name', trimmedName);
    }
    if (hasOwn(body, 'parent_name')) {
      addSet('parent_name', optionalTrimToNull(body.parent_name));
    }
    if (hasOwn(body, 'phone')) {
      addSet('phone', optionalTrimToNull(body.phone));
    }
    if (hasOwn(body, 'email')) {
      const rawEmail = optionalTrimToNull(body.email);
      addSet('email', rawEmail ? normalizeEmail(rawEmail) : null);
    }
    if (hasOwn(body, 'notes')) {
      addSet('notes', optionalTrimToNull(body.notes));
    }
    if (hasOwn(body, 'pay_by_bank_transfer')) {
      addSet('pay_by_bank_transfer', parsePayByBankFlag(body.pay_by_bank_transfer));
    }

    if (sets.length === 0) {
      return res.status(400).json({ message: 'Нет полей для обновления' });
    }

    values.push(studentId);
    const result = await pool.query(
      `UPDATE students
       SET ${sets.join(', ')}, updated_at = CURRENT_TIMESTAMP
       WHERE id = $${values.length}
       RETURNING *`,
      values
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ message: 'Студент не найден' });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Ошибка обновления студента:', error);
    res.status(500).json({ message: 'Ошибка обновления студента' });
  }
};

// Отправить ученика в выпускники (персонально для текущего пользователя).
export const archiveStudent = async (req, res) => {
  const userId = req.user.userId;
  const id = parsePositiveInt(req.params?.id);
  if (!id) return res.status(400).json({ message: 'Некорректный ID ученика' });

  try {
    const isSuper = isSuperuser(req.user);
    if (!isSuper) {
      const hasAccess = await assertTeacherHasStudentAccess(pool, userId, id);
      if (!hasAccess) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
    } else {
      const exists = await pool.query('SELECT 1 FROM students WHERE id = $1 LIMIT 1', [id]);
      if (exists.rows.length === 0) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
    }

    const result = await pool.query(
      `UPDATE teacher_students
       SET is_archived = true,
           archived_at = COALESCE(archived_at, CURRENT_TIMESTAMP)
       WHERE teacher_id = $1 AND student_id = $2
       RETURNING student_id, is_archived, archived_at`,
      [userId, id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({
        message: isSuper
          ? 'Связь текущего суперпользователя с учеником не найдена — сначала добавьте ученика к себе'
          : 'Связь с учеником не найдена',
      });
    }

    await logAccountingEvent({
      userId,
      eventType: 'student_archived',
      entityType: 'student',
      entityId: id,
      payload: { archivedAt: result.rows[0].archived_at },
    });

    return res.json({
      message: 'Ученик перенесён в выпускники',
      student_id: id,
      is_archived: true,
      archived_at: result.rows[0].archived_at,
    });
  } catch (error) {
    console.error('Ошибка архивации студента:', error);
    return res.status(500).json({ message: 'Ошибка архивации студента' });
  }
};

// Вернуть ученика из выпускников в активный список.
export const unarchiveStudent = async (req, res) => {
  const userId = req.user.userId;
  const id = parsePositiveInt(req.params?.id);
  if (!id) return res.status(400).json({ message: 'Некорректный ID ученика' });

  try {
    const isSuper = isSuperuser(req.user);
    if (!isSuper) {
      const hasAccess = await assertTeacherHasStudentAccess(pool, userId, id);
      if (!hasAccess) {
        return res.status(404).json({ message: 'Студент не найден' });
      }
    }

    const result = await pool.query(
      `UPDATE teacher_students
       SET is_archived = false,
           archived_at = NULL
       WHERE teacher_id = $1 AND student_id = $2
       RETURNING student_id, is_archived, archived_at`,
      [userId, id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({
        message: isSuper
          ? 'Связь текущего суперпользователя с учеником не найдена'
          : 'Связь с учеником не найдена',
      });
    }

    await logAccountingEvent({
      userId,
      eventType: 'student_unarchived',
      entityType: 'student',
      entityId: id,
      payload: {},
    });

    return res.json({
      message: 'Ученик возвращён в активные',
      student_id: id,
      is_archived: false,
      archived_at: null,
    });
  } catch (error) {
    console.error('Ошибка возврата студента из архива:', error);
    return res.status(500).json({ message: 'Ошибка возврата студента из архива' });
  }
};

// Удаление связи текущего пользователя с учеником (без полного удаления ученика из БД).
export const deleteStudent = async (req, res) => {
  const userId = req.user.userId;
  const id = parsePositiveInt(req.params?.id); // L9
  if (!id) {
    return res.status(400).json({ message: 'Некорректный ID ученика' });
  }

  const client = await pool.connect();
  let committed = false;
  try {
    try { await client.query('ROLLBACK'); } catch (_) {}
    await client.query('BEGIN');

    const isSuper = isSuperuser(req.user);
    if (!isSuper) {
      const hasAccess = await assertTeacherHasStudentAccess(client, userId, id);
      if (!hasAccess) {
        await client.query('ROLLBACK');
        return res.status(404).json({ message: 'Студент не найден' });
      }
    } else {
      const exists = await client.query('SELECT 1 FROM students WHERE id = $1 LIMIT 1', [id]);
      if (exists.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ message: 'Студент не найден' });
      }
    }

    const unlinkRes = await client.query(
      'DELETE FROM teacher_students WHERE teacher_id = $1 AND student_id = $2',
      [userId, id]
    );
    if (unlinkRes.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({
        message: isSuper
          ? 'Связь текущего суперпользователя с учеником не найдена'
          : 'Связь с учеником не найдена',
      });
    }
    await logAccountingEvent({
      userId,
      eventType: 'student_unlinked',
      entityType: 'student',
      entityId: id,
      payload: { removedLink: unlinkRes.rowCount > 0 },
    });

    await client.query('COMMIT');
    committed = true;
    return res.json({ message: 'Связь с учеником удалена' });
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('Ошибка удаления студента:', error);
    return res.status(500).json({ message: 'Ошибка удаления студента' });
  } finally {
    // L11: не делаем повторный ROLLBACK после успешного COMMIT.
    if (!committed) {
      try { await client.query('ROLLBACK'); } catch (_) {}
    }
    client.release();
  }
};

// Полное каскадное удаление отключено: стирало занятия/депозиты всех преподавателей
// и оставляло зарплату. В приложении — архив или удаление связи.
export const deleteStudentFull = async (_req, res) => {
  return res.status(410).json({
    message: 'Полное удаление ученика отключено. Используйте архив («выпускники») или удаление связи.',
  });
};

// Получение баланса студента
export const getStudentBalance = async (req, res) => {
  try {
    const userId = req.user.userId;
    const id = parsePositiveInt(req.params?.id);
    const mine = req.query.mine === '1' || req.query.mine === 'true';
    if (!id) return res.status(400).json({ message: 'Некорректный ID ученика' });

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

    const isSuper = isSuperuser(req.user);
    // Для преподавателя показываем баланс только по его операциям.
    // Для суперпользователя:
    // - mine=1 означает "только мои операции"
    // - без mine: полный баланс по ученику
    const result = isSuper
      ? (mine
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
          ))
      : await pool.query(
          `SELECT COALESCE((${sqlTeacherVisibleStudentBalance({ studentIdSql: '$1', teacherIdSql: '$2' })}), 0) AS balance`,
          [id, userId]
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
    const id = parsePositiveInt(req.params?.id);
    const mine = req.query.mine === '1' || req.query.mine === 'true';
    if (!id) return res.status(400).json({ message: 'Некорректный ID ученика' });
    const pagination = parseLimitOffset(req); // M17 (необязательные limit/offset)
    if (pagination.error) {
      return res.status(400).json({ message: pagination.error });
    }

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

    const isSuper = isSuperuser(req.user);
    let result;
    if (isSuper && mine) {
      const params = [id, userId];
      const pageClause = buildLimitOffsetSql(params, pagination);
      result = await pool.query(
        `SELECT t.*, l.lesson_date, l.lesson_time, ${sqlUserAccountingNameOrEmpty('u')} AS teacher_username
         FROM transactions t
         LEFT JOIN lessons l ON t.lesson_id = l.id
         LEFT JOIN users u ON t.created_by = u.id
         WHERE t.student_id = $1 AND t.created_by = $2
         ORDER BY t.created_at DESC${pageClause}`,
        params
      );
    } else if (isSuper) {
      const params = [id];
      const pageClause = buildLimitOffsetSql(params, pagination);
      result = await pool.query(
        `SELECT t.*, l.lesson_date, l.lesson_time, ${sqlUserAccountingNameOrEmpty('u')} AS teacher_username
         FROM transactions t
         LEFT JOIN lessons l ON t.lesson_id = l.id
         LEFT JOIN users u ON t.created_by = u.id
         WHERE t.student_id = $1
         ORDER BY t.created_at DESC${pageClause}`,
        params
      );
    } else {
      const params = [id, userId];
      const pageClause = buildLimitOffsetSql(params, pagination);
      result = await pool.query(
        `SELECT t.*, l.lesson_date, l.lesson_time, ${sqlUserAccountingNameOrEmpty('u')} AS teacher_username
         FROM transactions t
         LEFT JOIN lessons l ON t.lesson_id = l.id
         LEFT JOIN users u ON t.created_by = u.id
         WHERE t.student_id = $1
           AND (
             (t.type IN ('deposit', 'refund')
               AND (t.target_teacher_id = $2 OR t.target_teacher_id IS NULL))
             OR (t.type = 'lesson' AND t.created_by = $2)
           )
         ORDER BY t.created_at DESC${pageClause}`,
        params
      );
    }

    res.json(result.rows);
  } catch (error) {
    console.error('Ошибка получения транзакций:', error);
    res.status(500).json({ message: 'Ошибка получения истории транзакций' });
  }
};

