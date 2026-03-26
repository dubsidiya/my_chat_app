export const searchMessagesForChat = async (db, { chatIdNum, userId, limit, before }) => {
  const params = [chatIdNum, userId, limit];
  let beforeClause = '';
  if (Number.isFinite(before)) {
    beforeClause = ' AND m.id < $4';
    params.push(before);
  }

  return db.query(
    `
    SELECT
      m.id AS message_id,
      m.chat_id,
      m.user_id,
      m.key_version,
      m.content,
      m.message_type,
      m.image_url,
      m.created_at,
      COALESCE(u.display_name, u.email) AS sender_email,
      (mr.message_id IS NOT NULL) AS is_read
    FROM messages m
    JOIN users u ON u.id = m.user_id
    LEFT JOIN message_reads mr ON mr.message_id = m.id AND mr.user_id = $2
    WHERE m.chat_id = $1
      ${beforeClause}
    ORDER BY m.id DESC
    LIMIT $3
    `,
    params
  );
};

export const isMessageInChat = async (db, { messageId, chatIdNum }) => {
  return db.query(
    'SELECT 1 FROM messages WHERE id = $1 AND chat_id = $2',
    [messageId, chatIdNum]
  );
};

export const getAroundOlderMessages = async (db, { chatIdNum, messageId, limit, userId }) => {
  return db.query(
    `
    SELECT
      m.id,
      m.chat_id,
      m.user_id,
      m.content,
      m.image_url,
      m.original_image_url,
      m.file_url,
      m.file_name,
      m.file_size,
      m.file_mime,
      m.message_type,
      m.created_at,
      m.delivered_at,
      m.edited_at,
      m.reply_to_message_id,
      COALESCE(u.display_name, u.email) AS sender_email,
      u.avatar_url AS sender_avatar_url,
      pm.id IS NOT NULL AS is_pinned
    FROM messages m
    JOIN users u ON m.user_id = u.id
    LEFT JOIN pinned_messages pm ON pm.message_id = m.id AND pm.chat_id = $1
    WHERE m.chat_id = $1 AND m.id < $2
    AND NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE ub.blocker_id = $4 AND ub.blocked_id = m.user_id)
    ORDER BY m.id DESC
    LIMIT $3
    `,
    [chatIdNum, messageId, limit, userId]
  );
};

export const getAroundNewerMessages = async (db, { chatIdNum, messageId, limit, userId }) => {
  return db.query(
    `
    SELECT
      m.id,
      m.chat_id,
      m.user_id,
      m.content,
      m.image_url,
      m.original_image_url,
      m.file_url,
      m.file_name,
      m.file_size,
      m.file_mime,
      m.message_type,
      m.created_at,
      m.delivered_at,
      m.edited_at,
      m.reply_to_message_id,
      COALESCE(u.display_name, u.email) AS sender_email,
      u.avatar_url AS sender_avatar_url,
      pm.id IS NOT NULL AS is_pinned
    FROM messages m
    JOIN users u ON m.user_id = u.id
    LEFT JOIN pinned_messages pm ON pm.message_id = m.id AND pm.chat_id = $1
    WHERE m.chat_id = $1 AND m.id >= $2
    AND NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE ub.blocker_id = $4 AND ub.blocked_id = m.user_id)
    ORDER BY m.id ASC
    LIMIT $3
    `,
    [chatIdNum, messageId, limit, userId]
  );
};
