export const findMessageReadAt = async (db, { messageId, userId }) => {
  return db.query(
    'SELECT read_at FROM message_reads WHERE message_id = $1 AND user_id = $2',
    [messageId, userId]
  );
};

export const findReplyMessage = async (db, replyToMessageId) => {
  return db.query(
    `
    SELECT
      messages.id,
      messages.content,
      messages.image_url,
      messages.user_id,
      COALESCE(users.display_name, users.email) AS sender_email
    FROM messages
    JOIN users ON messages.user_id = users.id
    WHERE messages.id = $1
    `,
    [replyToMessageId]
  );
};

export const findMessageReactions = async (db, messageId) => {
  return db.query(
    `
    SELECT
      message_reactions.id,
      message_reactions.message_id,
      message_reactions.user_id,
      message_reactions.reaction,
      message_reactions.created_at,
      COALESCE(users.display_name, users.email) AS user_email
    FROM message_reactions
    JOIN users ON message_reactions.user_id = users.id
    WHERE message_reactions.message_id = $1
    ORDER BY message_reactions.created_at ASC
    `,
    [messageId]
  );
};

export const findForwardOriginChatName = async (db, messageId) => {
  return db.query(
    `
    SELECT mf.original_chat_id, c.name AS original_chat_name
    FROM message_forwards mf
    LEFT JOIN chats c ON c.id = mf.original_chat_id
    WHERE mf.message_id = $1
    LIMIT 1
    `,
    [messageId]
  );
};
