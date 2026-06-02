import pool from '../../db.js';

export const ensureMessageUserDeletionsTable = async (db = pool) => {
  await db.query(`
    CREATE TABLE IF NOT EXISTS message_user_deletions (
      message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (message_id, user_id)
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_message_user_deletions_user_id
      ON message_user_deletions(user_id)
  `);
};

/** SQL fragment: message row visible for user (alias = messages table alias). */
export const notHiddenForUserSql = (messageAlias, userIdParam) => `
  AND NOT EXISTS (
    SELECT 1 FROM message_user_deletions d
    WHERE d.message_id = ${messageAlias}.id AND d.user_id = ${userIdParam}
  )
`;

export const isDirectChat = async (db, chatId) => {
  const r = await db.query('SELECT is_group FROM chats WHERE id = $1', [chatId]);
  if (!r.rows.length) return false;
  return r.rows[0].is_group === false;
};

export const hideMessageForUser = async (db, messageId, userId) => {
  await ensureMessageUserDeletionsTable(db);
  await db.query(
    `INSERT INTO message_user_deletions (message_id, user_id)
     VALUES ($1, $2)
     ON CONFLICT (message_id, user_id) DO NOTHING`,
    [messageId, userId]
  );
};
