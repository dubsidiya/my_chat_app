export const findSenderDisplayName = async (db, userId) => {
  return db.query('SELECT COALESCE(display_name, email) AS n FROM users WHERE id = $1', [userId]);
};

export const findChatMembership = async (db, chatIdNum, userId) => {
  return db.query(
    'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
    [chatIdNum, userId]
  );
};
