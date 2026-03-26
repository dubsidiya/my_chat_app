import {
  findForwardOriginChatName,
  findMessageReactions,
  findMessageReadAt,
  findReplyMessage,
} from '../../repositories/messages/messageMetadataRepository.js';

export const enrichMessageRow = async (db, row, currentUserId) => {
  const readCheck = await findMessageReadAt(db, { messageId: row.id, userId: currentUserId });
  const isRead = readCheck.rows.length > 0;
  const readAt = isRead ? readCheck.rows[0].read_at : null;

  let replyToMessage = null;
  if (row.reply_to_message_id) {
    const replyCheck = await findReplyMessage(db, row.reply_to_message_id);
    if (replyCheck.rows.length > 0) {
      replyToMessage = {
        id: replyCheck.rows[0].id,
        content: replyCheck.rows[0].content,
        image_url: replyCheck.rows[0].image_url,
        user_id: replyCheck.rows[0].user_id,
        sender_email: replyCheck.rows[0].sender_email,
      };
    }
  }

  const reactionsResult = await findMessageReactions(db, row.id);
  const reactions = reactionsResult.rows.map((r) => ({
    id: r.id,
    message_id: r.message_id,
    user_id: r.user_id,
    reaction: r.reaction,
    created_at: r.created_at,
    user_email: r.user_email,
  }));

  const forwardCheck = await findForwardOriginChatName(db, row.id);
  const isForwarded = forwardCheck.rows.length > 0;
  const originalChatName = isForwarded ? (forwardCheck.rows[0].original_chat_name ?? null) : null;

  return {
    id: row.id,
    chat_id: row.chat_id,
    user_id: row.user_id,
    key_version: row.key_version ?? 1,
    content: row.content,
    image_url: row.image_url,
    original_image_url: row.original_image_url,
    file_url: row.file_url,
    file_name: row.file_name,
    file_size: row.file_size,
    file_mime: row.file_mime,
    message_type: row.message_type || 'text',
    created_at: row.created_at,
    delivered_at: row.delivered_at,
    edited_at: row.edited_at,
    is_read: isRead,
    read_at: readAt,
    reply_to_message_id: row.reply_to_message_id,
    reply_to_message: replyToMessage,
    is_pinned: row.is_pinned || false,
    reactions,
    is_forwarded: isForwarded,
    original_chat_name: originalChatName,
    sender_email: row.sender_email,
    sender_avatar_url: row.sender_avatar_url ?? null,
  };
};
