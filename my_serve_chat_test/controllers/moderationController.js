import pool from '../db.js';
import { parsePositiveInt } from '../utils/sanitize.js';

export const ensureUserBlocksTable = async () => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_blocks (
      blocker_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      blocked_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (blocker_id, blocked_id),
      CHECK (blocker_id <> blocked_id)
    )
  `);
};

const ensureContentReportsTable = async () => {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS content_reports (
      id SERIAL PRIMARY KEY,
      message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
      reporter_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(message_id, reporter_id)
    )
  `);
};

export const reportMessage = async (req, res) => {
  try {
    await ensureContentReportsTable();
    const reporterId = req.user.userId;
    const messageId = parsePositiveInt(req.params.messageId);
    if (!messageId) {
      return res.status(400).json({ message: 'Некорректный ID сообщения' });
    }
    const msgCheck = await pool.query('SELECT id, chat_id FROM messages WHERE id = $1', [messageId]);
    if (msgCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение не найдено' });
    }
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [msgCheck.rows[0].chat_id, reporterId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Нет доступа к этому чату' });
    }
    await pool.query(
      'INSERT INTO content_reports (message_id, reporter_id) VALUES ($1, $2) ON CONFLICT (message_id, reporter_id) DO NOTHING',
      [messageId, reporterId]
    );
    res.status(200).json({ reported: true, message: 'Жалоба отправлена. Модерация рассмотрит в течение 24 часов.' });
  } catch (err) {
    console.error('reportMessage:', err);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const blockUser = async (req, res) => {
  try {
    await ensureUserBlocksTable();
    const blockerId = req.user.userId;
    const rawId = req.body?.user_id ?? req.body?.userId ?? req.params.userId;
    const blockedId = parsePositiveInt(rawId);
    if (!blockedId || blockedId === blockerId) {
      return res.status(400).json({ message: 'Некорректный пользователь' });
    }
    const userCheck = await pool.query('SELECT id FROM users WHERE id = $1', [blockedId]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    await pool.query(
      'INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT (blocker_id, blocked_id) DO NOTHING',
      [blockerId, blockedId]
    );
    res.status(200).json({ blocked: true, message: 'Пользователь заблокирован. Его сообщения скрыты.' });
  } catch (err) {
    console.error('blockUser:', err);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const getBlockedUserIds = async (req, res) => {
  try {
    await ensureUserBlocksTable();
    const blockerId = req.user.userId;
    const result = await pool.query(
      'SELECT blocked_id FROM user_blocks WHERE blocker_id = $1',
      [blockerId]
    );
    res.status(200).json({ blocked_ids: result.rows.map((r) => r.blocked_id) });
  } catch (err) {
    console.error('getBlockedUserIds:', err);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};
