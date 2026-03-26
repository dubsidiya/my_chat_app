export const findChatCreatorId = async (db, chatId) => {
  return db.query('SELECT created_by FROM chats WHERE id = $1', [chatId]);
};

export const findChatMemberRole = async (db, chatId, userId) => {
  return db.query(
    'SELECT role FROM chat_users WHERE chat_id = $1 AND user_id = $2',
    [chatId, userId]
  );
};

export const findChatMembership = async (db, chatId, userId) => {
  return db.query(
    'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
    [chatId, userId]
  );
};

export const findChatMemberIds = async (db, chatId) => {
  return db.query(
    'SELECT user_id FROM chat_users WHERE chat_id = $1 ORDER BY user_id ASC',
    [chatId]
  );
};
