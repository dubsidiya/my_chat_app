import pool from '../db.js';
import { isSuperuser } from '../middleware/auth.js';
import { logAccountingEvent } from '../utils/accountingAudit.js';
import {
  createTeacherBalanceTransaction,
  getTeacherBalance,
  listTeacherBalanceTransactions,
  listTeachersWithBalances,
  syncTeacherBalancesForPeriod,
  TEACHER_BALANCE_SYNC_FROM,
  TEACHER_BALANCE_TYPE_LABELS,
  teacherBalanceSyncToToday,
} from '../services/accounting/teacherBalanceService.js';
import { sqlUserAccountingName } from '../utils/userAccountingDisplaySql.js';

const mapTransactionRow = (row) => ({
  id: row.id,
  teacher_id: row.teacher_id,
  amount: Number(row.amount),
  type: row.type,
  type_label: TEACHER_BALANCE_TYPE_LABELS[row.type] || row.type,
  description: row.description || '',
  report_id: row.report_id,
  lesson_id: row.lesson_id,
  created_by: row.created_by,
  created_by_name: row.created_by_name || '',
  created_at: row.created_at,
});

/** GET /reports/balance — рабочий баланс текущего преподавателя */
export const getMyTeacherBalance = async (req, res) => {
  try {
    const teacherId = req.user.userId;
    const balance = await getTeacherBalance(pool, teacherId);
    return res.json({ teacher_id: teacherId, balance });
  } catch (error) {
    console.error('getMyTeacherBalance:', error);
    return res.status(500).json({ message: 'Ошибка загрузки баланса' });
  }
};

/** GET /reports/balance/transactions */
export const getMyTeacherBalanceTransactions = async (req, res) => {
  try {
    const teacherId = req.user.userId;
    const limit = req.query.limit;
    const offset = req.query.offset;
    const balance = await getTeacherBalance(pool, teacherId);
    const rows = await listTeacherBalanceTransactions(pool, teacherId, { limit, offset });
    return res.json({
      teacher_id: teacherId,
      balance,
      transactions: rows.map(mapTransactionRow),
    });
  } catch (error) {
    console.error('getMyTeacherBalanceTransactions:', error);
    return res.status(500).json({ message: 'Ошибка загрузки истории баланса' });
  }
};

/** GET /admin/accounting/teacher-balances */
export const listTeacherBalancesAdmin = async (req, res) => {
  try {
    const teachers = await listTeachersWithBalances(pool);
    return res.json({ teachers });
  } catch (error) {
    console.error('listTeacherBalancesAdmin:', error);
    return res.status(500).json({ message: 'Ошибка списка балансов' });
  }
};

/** GET /admin/accounting/teacher-balances/:teacherId */
export const getTeacherBalanceAdmin = async (req, res) => {
  try {
    const teacherId = parseInt(req.params.teacherId, 10);
    if (!Number.isFinite(teacherId)) {
      return res.status(400).json({ message: 'Некорректный id преподавателя' });
    }
    const userRes = await pool.query(
      `SELECT id, ${sqlUserAccountingName('u')} AS label FROM users u WHERE u.id = $1`,
      [teacherId]
    );
    if (userRes.rows.length === 0) {
      return res.status(404).json({ message: 'Преподаватель не найден' });
    }
    const balance = await getTeacherBalance(pool, teacherId);
    const limit = req.query.limit;
    const offset = req.query.offset;
    const rows = await listTeacherBalanceTransactions(pool, teacherId, { limit, offset });
    return res.json({
      teacher_id: teacherId,
      label: userRes.rows[0].label || '',
      balance,
      transactions: rows.map(mapTransactionRow),
    });
  } catch (error) {
    console.error('getTeacherBalanceAdmin:', error);
    return res.status(500).json({ message: 'Ошибка загрузки баланса преподавателя' });
  }
};

/** POST /admin/accounting/teacher-balances/:teacherId/transactions */
export const postTeacherBalanceTransactionAdmin = async (req, res) => {
  if (!isSuperuser(req.user)) {
    return res.status(403).json({ message: 'Требуется доступ суперпользователя' });
  }
  const teacherId = parseInt(req.params.teacherId, 10);
  if (!Number.isFinite(teacherId)) {
    return res.status(400).json({ message: 'Некорректный id преподавателя' });
  }
  const { type, amount, description } = req.body || {};
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await createTeacherBalanceTransaction(client, {
      teacherId,
      type,
      amount,
      description,
      createdBy: req.user.userId,
    });
    if (result.error) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: result.error });
    }
    await logAccountingEvent({
      client,
      userId: req.user.userId,
      eventType: 'teacher_balance_transaction',
      entityType: 'teacher_balance',
      entityId: result.row.id,
      payload: {
        teacherId,
        type,
        amount: Number(result.row.amount),
        description: result.row.description,
      },
    });
    await client.query('COMMIT');
    const balance = await getTeacherBalance(pool, teacherId);
    return res.status(201).json({
      transaction: mapTransactionRow({ ...result.row, created_by_name: '' }),
      balance,
    });
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('postTeacherBalanceTransactionAdmin:', error);
    return res.status(500).json({ message: 'Ошибка создания операции' });
  } finally {
    client.release();
  }
};

/** POST /admin/accounting/teacher-balances/sync — всегда 01.06.2026 … сегодня */
export const syncTeacherBalancesAdmin = async (req, res) => {
  if (!isSuperuser(req.user)) {
    return res.status(403).json({ message: 'Требуется доступ суперпользователя' });
  }
  const from = TEACHER_BALANCE_SYNC_FROM;
  const to = teacherBalanceSyncToToday();
  if (from > to) {
    return res.status(400).json({ message: 'Дата начала синхронизации позже текущего дня' });
  }
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const stats = await syncTeacherBalancesForPeriod(client, {
      from,
      to,
      actorUserId: req.user.userId,
    });
    await logAccountingEvent({
      client,
      userId: req.user.userId,
      eventType: 'teacher_balance_sync',
      entityType: 'teacher_balance',
      entityId: null,
      payload: { from, to, ...stats },
    });
    await client.query('COMMIT');
    return res.json({ from, to, ...stats });
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    console.error('syncTeacherBalancesAdmin:', error);
    return res.status(500).json({ message: 'Ошибка синхронизации балансов' });
  } finally {
    client.release();
  }
};
