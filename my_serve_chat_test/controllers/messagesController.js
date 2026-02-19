import pool from '../db.js';
import { getWebSocketClients } from '../websocket/websocket.js';
import { uploadImage as uploadImageMiddleware, uploadToCloud, deleteImage } from '../utils/uploadImage.js';
import { uploadFileToCloud, deleteFile as deleteCloudFile } from '../utils/uploadFile.js';
import { sendPushToTokens } from '../utils/pushNotifications.js';

// Лимит длины текста сообщения (защита от DoS и переполнения БД)
const MAX_MESSAGE_CONTENT_LENGTH = 65535;

// Как видят отправителя другие (ник или логин)
const getSenderDisplayName = async (userId) => {
  const r = await pool.query('SELECT COALESCE(display_name, email) AS n FROM users WHERE id = $1', [userId]);
  return r.rows[0]?.n ?? null;
};

const ensureChatMember = async (chatId, userId) => {
  const chatIdNum = parseInt(chatId, 10);
  if (isNaN(chatIdNum)) return { ok: false, status: 400, message: 'Некорректный chatId' };

  const memberCheck = await pool.query(
    'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
    [chatIdNum, userId]
  );
  if (memberCheck.rows.length === 0) {
    return { ok: false, status: 403, message: 'Вы не являетесь участником этого чата' };
  }
  return { ok: true, chatIdNum };
};

export const getMessages = async (req, res) => {
  const chatId = req.params.chatId;
  const currentUserId = req.user.userId;
  
  // Параметры пагинации
  const requestedLimit = parseInt(req.query.limit);
  const requestedOffset = parseInt(req.query.offset);
  const limit = Math.min(Math.max(Number.isFinite(requestedLimit) ? requestedLimit : 50, 1), 200);
  const offset = Math.max(Number.isFinite(requestedOffset) ? requestedOffset : 0, 0);
  const beforeMessageId = req.query.before; // ID сообщения, до которого загружать (для cursor-based)

  try {
    const membership = await ensureChatMember(chatId, currentUserId);
    if (!membership.ok) {
      return res.status(membership.status).json({ message: membership.message });
    }
    const chatIdNum = membership.chatIdNum;

    const { ensureUserBlocksTable } = await import('./moderationController.js');
    await ensureUserBlocksTable();

    let result;
    let totalCountResult;

    if (beforeMessageId) {
      const beforeIdNum = parseInt(beforeMessageId, 10);
      if (isNaN(beforeIdNum)) {
        return res.status(400).json({ message: 'Некорректный параметр before' });
      }
      // Cursor-based pagination: загружаем сообщения до указанного ID (старые сообщения)
      // Загружаем на 1 больше, чтобы проверить, есть ли еще сообщения
      result = await pool.query(`
        SELECT 
          messages.id,
          messages.chat_id,
          messages.user_id,
          messages.content,
          messages.image_url,
          messages.original_image_url,
          messages.file_url,
          messages.file_name,
          messages.file_size,
          messages.file_mime,
          messages.message_type,
          messages.created_at,
          messages.delivered_at,
          messages.edited_at,
          messages.reply_to_message_id,
          COALESCE(users.display_name, users.email) AS sender_email,
          users.avatar_url AS sender_avatar_url,
          pinned_messages.id IS NOT NULL AS is_pinned
        FROM messages
        JOIN users ON messages.user_id = users.id
        LEFT JOIN pinned_messages ON pinned_messages.message_id = messages.id AND pinned_messages.chat_id = $1
        WHERE messages.chat_id = $1 AND messages.id < $2
        AND NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE ub.blocker_id = $4 AND ub.blocked_id = messages.user_id)
        ORDER BY messages.id DESC
        LIMIT $3
      `, [chatIdNum, beforeIdNum, limit + 1, currentUserId]);
      
      // Проверяем, есть ли еще сообщения (если получили больше чем limit)
      const hasMoreMessages = result.rows.length > limit;
      
      // Берем только limit сообщений
      if (hasMoreMessages) {
        result.rows = result.rows.slice(0, limit);
      }
      
      // Получаем общее количество для информации
      totalCountResult = await pool.query(
        'SELECT COUNT(*) as total FROM messages WHERE chat_id = $1',
        [chatIdNum]
      );
    } else {
      // Offset-based pagination: загружаем последние N сообщений
      // Сначала получаем общее количество сообщений
      totalCountResult = await pool.query(
        'SELECT COUNT(*) as total FROM messages WHERE chat_id = $1',
        [chatIdNum]
      );
      
      const totalCount = parseInt(totalCountResult.rows[0].total);
      const actualOffset = Math.max(0, totalCount - limit - offset);
      
      result = await pool.query(`
        SELECT 
          messages.id,
          messages.chat_id,
          messages.user_id,
          messages.content,
          messages.image_url,
          messages.original_image_url,
          messages.file_url,
          messages.file_name,
          messages.file_size,
          messages.file_mime,
          messages.message_type,
          messages.created_at,
          messages.delivered_at,
          messages.edited_at,
          messages.reply_to_message_id,
          COALESCE(users.display_name, users.email) AS sender_email,
          users.avatar_url AS sender_avatar_url,
          pinned_messages.id IS NOT NULL AS is_pinned
        FROM messages
        JOIN users ON messages.user_id = users.id
        LEFT JOIN pinned_messages ON pinned_messages.message_id = messages.id AND pinned_messages.chat_id = $1
        WHERE messages.chat_id = $1
        AND NOT EXISTS (SELECT 1 FROM user_blocks ub WHERE ub.blocker_id = $4 AND ub.blocked_id = messages.user_id)
        ORDER BY messages.created_at ASC
        LIMIT $2 OFFSET $3
      `, [chatIdNum, limit, actualOffset, currentUserId]);
    }
    
    const totalCount = parseInt(totalCountResult.rows[0].total);

    // Форматируем в формат, который ожидает приложение
    const formattedMessages = await Promise.all(result.rows.map(async (row) => {
      // Проверяем, прочитал ли текущий пользователь это сообщение
      const readCheck = await pool.query(
        'SELECT read_at FROM message_reads WHERE message_id = $1 AND user_id = $2',
        [row.id, currentUserId]
      );
      
      const isRead = readCheck.rows.length > 0;
      const readAt = isRead ? readCheck.rows[0].read_at : null;
      
      // ✅ Получаем сообщение, на которое отвечают (если есть)
      let replyToMessage = null;
      if (row.reply_to_message_id) {
        const replyCheck = await pool.query(`
          SELECT 
            messages.id,
            messages.content,
            messages.image_url,
            messages.user_id,
            COALESCE(users.display_name, users.email) AS sender_email
          FROM messages
          JOIN users ON messages.user_id = users.id
          WHERE messages.id = $1
        `, [row.reply_to_message_id]);
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
      
      // ✅ Получаем реакции на сообщение
      const reactionsResult = await pool.query(`
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
      `, [row.id]);
      
      const reactions = reactionsResult.rows.map(r => ({
        id: r.id,
        message_id: r.message_id,
        user_id: r.user_id,
        reaction: r.reaction,
        created_at: r.created_at,
        user_email: r.user_email,
      }));
      
      // ✅ Проверяем, переслано ли сообщение
      const forwardCheck = await pool.query(
        'SELECT original_chat_id FROM message_forwards WHERE message_id = $1 LIMIT 1',
        [row.id]
      );
      const isForwarded = forwardCheck.rows.length > 0;
      let originalChatName = null;
      if (isForwarded && forwardCheck.rows[0].original_chat_id) {
        const chatCheck = await pool.query(
          'SELECT name FROM chats WHERE id = $1',
          [forwardCheck.rows[0].original_chat_id]
        );
        if (chatCheck.rows.length > 0) {
          originalChatName = chatCheck.rows[0].name;
        }
      }
      
      return {
        id: row.id,
        chat_id: row.chat_id,
        user_id: row.user_id,
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
        reactions: reactions,
        is_forwarded: isForwarded,
        original_chat_name: originalChatName,
        sender_email: row.sender_email,
        sender_avatar_url: row.sender_avatar_url ?? null
      };
    }));

    // Определяем, есть ли еще сообщения для загрузки
    let hasMore;
    if (beforeMessageId) {
      // Для cursor-based: если получили полную страницу, возможно есть еще
      // Проверяем, есть ли сообщения с ID меньше самого маленького в результате
      hasMore = formattedMessages.length === limit;
      if (hasMore && formattedMessages.length > 0) {
        const minId = Math.min(...formattedMessages.map(m => m.id));
        const checkResult = await pool.query(
          'SELECT 1 FROM messages WHERE chat_id = $1 AND id < $2 LIMIT 1',
          [chatIdNum, minId]
        );
        hasMore = checkResult.rows.length > 0;
      }
    } else {
      // Для offset-based: проверяем, есть ли еще сообщения после текущей страницы
      hasMore = (offset + limit) < totalCount;
    }

    // Находим ID самого старого сообщения в результате (для cursor-based)
    // Это будет минимальный ID, так как мы загружаем старые сообщения
    const oldestMessageId = formattedMessages.length > 0 
      ? Math.min(...formattedMessages.map(m => m.id))
      : null;

    res.json({
      messages: formattedMessages,
      pagination: {
        hasMore: hasMore,
        totalCount: totalCount,
        limit: limit,
        offset: offset,
        oldestMessageId: oldestMessageId, // Для следующего запроса с before
      }
    });
  } catch (error) {
    console.error('Ошибка получения сообщений:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Поиск сообщений в чате
export const searchMessages = async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const userId = req.user.userId;
    const q = (req.query.q || '').toString().trim();
    const requestedLimit = parseInt(req.query.limit);
    const limit = Math.min(Math.max(Number.isFinite(requestedLimit) ? requestedLimit : 20, 1), 50);
    const before = req.query.before ? parseInt(req.query.before, 10) : null;

    if (!q) {
      return res.status(400).json({ message: 'Параметр q обязателен' });
    }
    if (q.length > 100) {
      return res.status(400).json({ message: 'Слишком длинный запрос' });
    }

    const membership = await ensureChatMember(chatId, userId);
    if (!membership.ok) {
      return res.status(membership.status).json({ message: membership.message });
    }
    const chatIdNum = membership.chatIdNum;

    const params = [chatIdNum, `%${q}%`, limit, userId];
    let beforeClause = '';
    if (Number.isFinite(before)) {
      beforeClause = ' AND m.id < $5';
      params.push(before);
    }

    const result = await pool.query(
      `
      SELECT
        m.id AS message_id,
        m.content,
        m.message_type,
        m.image_url,
        m.created_at,
        COALESCE(u.display_name, u.email) AS sender_email,
        (mr.message_id IS NOT NULL) AS is_read
      FROM messages m
      JOIN users u ON u.id = m.user_id
      LEFT JOIN message_reads mr ON mr.message_id = m.id AND mr.user_id = $4
      WHERE m.chat_id = $1
        AND m.content ILIKE $2
        ${beforeClause}
      ORDER BY m.id DESC
      LIMIT $3
      `,
      params
    );

    const queryLower = q.toLowerCase();
    const items = result.rows.map((row) => {
      const content = (row.content || '').toString();
      const idx = content.toLowerCase().indexOf(queryLower);
      let snippet = content;
      if (idx >= 0) {
        const start = Math.max(0, idx - 40);
        const end = Math.min(content.length, idx + queryLower.length + 40);
        snippet = content.substring(start, end);
        if (start > 0) snippet = '…' + snippet;
        if (end < content.length) snippet = snippet + '…';
      } else if (content.length > 120) {
        snippet = content.substring(0, 120) + '…';
      }

      return {
        message_id: row.message_id?.toString(),
        content_snippet: snippet,
        message_type: row.message_type,
        image_url: row.image_url,
        created_at: row.created_at,
        sender_email: row.sender_email,
        is_read: row.is_read === true,
      };
    });

    return res.status(200).json({ results: items });
  } catch (error) {
    console.error('Ошибка searchMessages:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Получить окно сообщений вокруг конкретного messageId
export const getMessagesAround = async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const messageId = parseInt(req.params.messageId, 10);
    const userId = req.user.userId;
    const requestedLimit = parseInt(req.query.limit);
    const limit = Math.min(Math.max(Number.isFinite(requestedLimit) ? requestedLimit : 50, 10), 200);

    if (isNaN(messageId)) {
      return res.status(400).json({ message: 'Некорректный messageId' });
    }

    const membership = await ensureChatMember(chatId, userId);
    if (!membership.ok) {
      return res.status(membership.status).json({ message: membership.message });
    }
    const chatIdNum = membership.chatIdNum;

    const { ensureUserBlocksTable } = await import('./moderationController.js');
    await ensureUserBlocksTable();

    // Проверяем, что сообщение принадлежит чату
    const msgCheck = await pool.query(
      'SELECT 1 FROM messages WHERE id = $1 AND chat_id = $2',
      [messageId, chatIdNum]
    );
    if (msgCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение не найдено' });
    }

    const half = Math.floor(limit / 2);

    const older = await pool.query(
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
      [chatIdNum, messageId, half, userId]
    );

    const newer = await pool.query(
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
      [chatIdNum, messageId, half + 1, userId]
    );

    const rows = [...older.rows.reverse(), ...newer.rows];

    // Обогащаем данными как в getMessages (read status, reply, reactions, forwarded, original chat name)
    const formattedMessages = await Promise.all(rows.map(async (row) => {
      const readCheck = await pool.query(
        'SELECT read_at FROM message_reads WHERE message_id = $1 AND user_id = $2',
        [row.id, userId]
      );
      const isRead = readCheck.rows.length > 0;
      const readAt = isRead ? readCheck.rows[0].read_at : null;

      let replyToMessage = null;
      if (row.reply_to_message_id) {
        const replyCheck = await pool.query(`
          SELECT 
            m.id,
            m.content,
            m.image_url,
            m.user_id,
            COALESCE(u.display_name, u.email) AS sender_email
          FROM messages m
          JOIN users u ON m.user_id = u.id
          WHERE m.id = $1
        `, [row.reply_to_message_id]);
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

      const reactionsResult = await pool.query(`
        SELECT 
          mr.id,
          mr.message_id,
          mr.user_id,
          mr.reaction,
          mr.created_at,
          COALESCE(u.display_name, u.email) AS user_email
        FROM message_reactions mr
        JOIN users u ON mr.user_id = u.id
        WHERE mr.message_id = $1
        ORDER BY mr.created_at ASC
      `, [row.id]);

      const reactions = reactionsResult.rows.map(r => ({
        id: r.id,
        message_id: r.message_id,
        user_id: r.user_id,
        reaction: r.reaction,
        created_at: r.created_at,
        user_email: r.user_email,
      }));

      const forwardCheck = await pool.query(
        'SELECT original_chat_id FROM message_forwards WHERE message_id = $1 LIMIT 1',
        [row.id]
      );
      const isForwarded = forwardCheck.rows.length > 0;
      let originalChatName = null;
      if (isForwarded && forwardCheck.rows[0].original_chat_id) {
        const chatCheck = await pool.query(
          'SELECT name FROM chats WHERE id = $1',
          [forwardCheck.rows[0].original_chat_id]
        );
        if (chatCheck.rows.length > 0) {
          originalChatName = chatCheck.rows[0].name;
        }
      }

      return {
        id: row.id,
        chat_id: row.chat_id,
        user_id: row.user_id,
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
        reactions: reactions,
        is_forwarded: isForwarded,
        original_chat_name: originalChatName,
        sender_email: row.sender_email,
        sender_avatar_url: row.sender_avatar_url ?? null
      };
    }));

    return res.status(200).json({
      messages: formattedMessages,
      targetMessageId: messageId.toString(),
    });
  } catch (error) {
    console.error('Ошибка getMessagesAround:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const sendMessage = async (req, res) => {
  // Приложение отправляет: { chat_id, content, image_url, reply_to_message_id, forward_from_message_id, forward_to_chat_ids }
  const { chat_id, content, image_url, original_image_url, file_url, file_name, file_size, file_mime, reply_to_message_id, forward_from_message_id, forward_to_chat_ids } = req.body;
  
  // userId берем из токена (безопасно)
  const user_id = req.user.userId;

  if (process.env.NODE_ENV === 'development') {
    console.log('📨 sendMessage called:', {
      chat_id,
      content,
      image_url,
      original_image_url,
      reply_to_message_id,
      user_id,
    });
  }

  if (!chat_id || (!content && !image_url && !file_url)) {
    return res.status(400).json({ message: 'Укажите chat_id и content или image_url или file_url' });
  }

  const contentStr = content != null ? String(content) : '';
  if (contentStr.length > MAX_MESSAGE_CONTENT_LENGTH) {
    return res.status(400).json({ message: `Текст сообщения не более ${MAX_MESSAGE_CONTENT_LENGTH} символов` });
  }

  // Пока упрощаем: нельзя одновременно image и file в одном сообщении (чтобы не плодить message_type)
  if (image_url && file_url) {
    return res.status(400).json({ message: 'Нельзя отправлять изображение и файл в одном сообщении' });
  }

  // Лимит длины URL и имени файла (защита от DoS и переполнения БД)
  const MAX_URL_LENGTH = 2048;
  const MAX_FILE_NAME_LENGTH = 255;
  if (image_url && String(image_url).length > MAX_URL_LENGTH) {
    return res.status(400).json({ message: 'Ссылка на изображение слишком длинная' });
  }
  if (original_image_url && String(original_image_url).length > MAX_URL_LENGTH) {
    return res.status(400).json({ message: 'Ссылка на изображение слишком длинная' });
  }
  if (file_url && String(file_url).length > MAX_URL_LENGTH) {
    return res.status(400).json({ message: 'Ссылка на файл слишком длинная' });
  }
  if (file_name && String(file_name).length > MAX_FILE_NAME_LENGTH) {
    return res.status(400).json({ message: 'Имя файла не более 255 символов' });
  }
  
  // ✅ Если пересылка сообщений (лимит числа чатов — защита от DoS)
  if (forward_from_message_id && forward_to_chat_ids && Array.isArray(forward_to_chat_ids)) {
    const MAX_FORWARD_CHATS = 20;
    const toChatIds = forward_to_chat_ids.slice(0, MAX_FORWARD_CHATS);
    return await forwardMessages(req, res, forward_from_message_id, toChatIds, user_id);
  }

  try {
    // Преобразуем chat_id в число, если это строка
    const chatIdNum = parseInt(chat_id, 10);
    if (isNaN(chatIdNum)) {
      console.error('❌ Invalid chat_id:', chat_id);
      return res.status(400).json({ message: 'Некорректный chat_id' });
    }

    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatIdNum, user_id]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    // Определяем тип сообщения
    let message_type = 'text';
    if (file_url && content) {
      message_type = 'text_file';
    } else if (file_url) {
      message_type = 'file';
    } else if (image_url && content) {
      message_type = 'text_image';
    } else if (image_url) {
      message_type = 'image';
    }

    // Используем user_id из токена (безопасно)
    // Преобразуем reply_to_message_id в число, если это строка
    const replyToMessageIdNum = reply_to_message_id ? parseInt(reply_to_message_id, 10) : null;
    
    if (process.env.NODE_ENV === 'development') {
      console.log('📝 Inserting message:', {
        chat_id: chatIdNum,
        user_id,
        content: content || '',
        image_url: image_url || null,
        original_image_url: original_image_url || null,
        message_type,
        reply_to_message_id: replyToMessageIdNum
      });
    }

    const result = await pool.query(`
      INSERT INTO messages (chat_id, user_id, content, image_url, original_image_url, file_url, file_name, file_size, file_mime, message_type, delivered_at, reply_to_message_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, CURRENT_TIMESTAMP, $11)
      RETURNING id, chat_id, user_id, content, image_url, original_image_url, file_url, file_name, file_size, file_mime, message_type, created_at, delivered_at, reply_to_message_id
    `, [
      chatIdNum,
      user_id,
      contentStr || '',
      image_url || null,
      original_image_url || null,
      file_url || null,
      file_name || null,
      file_size ? parseInt(file_size, 10) : null,
      file_mime || null,
      message_type,
      replyToMessageIdNum,
    ]);

    const message = result.rows[0];
    const senderEmail = (await getSenderDisplayName(req.user.userId)) || req.user.email;
    let senderAvatarUrl = null;
    try {
      const avatarRow = await pool.query('SELECT avatar_url FROM users WHERE id = $1', [message.user_id]);
      senderAvatarUrl = avatarRow.rows[0]?.avatar_url ?? null;
    } catch (_) { /* колонка avatar_url может отсутствовать до миграции */ }

    // ✅ Получаем сообщение, на которое отвечают (если есть)
    let replyToMessage = null;
    if (message.reply_to_message_id) {
      const replyCheck = await pool.query(`
        SELECT 
          messages.id,
          messages.content,
          messages.image_url,
          messages.user_id,
          COALESCE(users.display_name, users.email) AS sender_email
        FROM messages
        JOIN users ON messages.user_id = users.id
        WHERE messages.id = $1
      `, [message.reply_to_message_id]);
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
    
    const response = {
      id: message.id,
      chat_id: message.chat_id,
      user_id: message.user_id,
      content: message.content,
      image_url: message.image_url,
      original_image_url: message.original_image_url,
      file_url: message.file_url,
      file_name: message.file_name,
      file_size: message.file_size,
      file_mime: message.file_mime,
      message_type: message.message_type,
      created_at: message.created_at,
      delivered_at: message.delivered_at,
      edited_at: null,
      is_read: false,
      read_at: null,
      reply_to_message_id: message.reply_to_message_id,
      reply_to_message: replyToMessage,
      is_pinned: false,
      reactions: [],
      is_forwarded: false,
      sender_email: senderEmail,
      sender_avatar_url: senderAvatarUrl
    };

    // Отправляем сообщение через WebSocket всем участникам чата
    try {
      const clients = getWebSocketClients();
      const members = await pool.query(
        'SELECT user_id FROM chat_users WHERE chat_id = $1',
        [chatIdNum]
      );

      // Гарантируем строки и отсутствие null для надёжной доставки на клиент
      const wsMessage = {
        type: 'message',
        id: message.id,
        chat_id: String(message.chat_id),
        user_id: message.user_id,
        content: message.content != null ? String(message.content) : '',
        image_url: message.image_url ?? null,
        original_image_url: message.original_image_url ?? null,
        file_url: message.file_url ?? null,
        file_name: message.file_name ?? null,
        file_size: message.file_size ?? null,
        file_mime: message.file_mime ?? null,
        message_type: message.message_type || 'text',
        created_at: message.created_at instanceof Date ? message.created_at.toISOString() : String(message.created_at ?? ''),
        delivered_at: message.delivered_at != null ? (message.delivered_at instanceof Date ? message.delivered_at.toISOString() : String(message.delivered_at)) : null,
        edited_at: null,
        is_read: false,
        read_at: null,
        sender_email: senderEmail || '',
        sender_avatar_url: senderAvatarUrl ?? null
      };

      if (process.env.NODE_ENV === 'development') {
        console.log('Sending WebSocket message to chat:', chatIdNum);
        console.log('Chat members:', members.rows.map(r => r.user_id));
        console.log('Connected clients:', Array.from(clients.keys()));
      }

      const wsMessageString = JSON.stringify(wsMessage);
      
      let sentCount = 0;
      members.rows.forEach(row => {
        const userIdStr = row.user_id.toString();
        const client = clients.get(userIdStr);
        if (client && client.readyState === 1) { // WebSocket.OPEN
          try {
            client.send(wsMessageString);
            sentCount++;
            if (process.env.NODE_ENV === 'development') {
              console.log(`Message sent to user ${userIdStr}`);
            }
          } catch (sendError) {
            console.error(`Error sending to user ${userIdStr}:`, sendError);
          }
        } else {
          if (process.env.NODE_ENV === 'development') {
            console.log(`User ${userIdStr} not connected or connection not open (readyState: ${client?.readyState})`);
          }
        }
      });
      
      if (process.env.NODE_ENV === 'development') {
        console.log(`WebSocket message sent to ${sentCount} out of ${members.rows.length} members`);
      }
    } catch (wsError) {
      console.error('Ошибка отправки через WebSocket:', wsError);
      // Не прерываем выполнение, сообщение уже сохранено в БД
    }

    // Push-уведомления: участникам чата (кроме отправителя) с сохранённым FCM-токеном
    try {
      const otherMemberIds = members.rows
        .map(r => r.user_id)
        .filter(id => id !== user_id);
      if (otherMemberIds.length > 0) {
        const tokensResult = await pool.query(
          'SELECT fcm_token FROM users WHERE id = ANY($1) AND fcm_token IS NOT NULL AND fcm_token != \'\'',
          [otherMemberIds]
        );
        const tokens = tokensResult.rows.map(r => r.fcm_token);
        if (tokens.length > 0) {
          const chatInfo = await pool.query('SELECT name, is_group FROM chats WHERE id = $1', [chatIdNum]);
          const chatName = chatInfo.rows[0]?.name || 'Чат';
          const isGroup = chatInfo.rows[0]?.is_group ?? true;
          const title = 'Новое сообщение';
          const body = `${senderEmail}: ${(contentStr || '').trim().slice(0, 80)}${(contentStr || '').length > 80 ? '…' : ''}`.trim() || 'Сообщение в чате';
          await sendPushToTokens(tokens, title, body, {
            chatId: chatIdNum.toString(),
            messageId: message.id.toString(),
            chatName,
            isGroup: isGroup ? '1' : '0',
          });
        }
      }
    } catch (pushErr) {
      console.error('Ошибка отправки push:', pushErr.message);
    }

    res.status(201).json(response);
  } catch (error) {
    console.error('Ошибка отправки сообщения:', error);
    res.status(500).json({ 
      message: 'Ошибка сервера',
    });
  }
};

// ✅ Редактирование сообщения
export const editMessage = async (req, res) => {
  const messageId = req.params.messageId;
  const userId = req.user.userId;
  const { content, image_url } = req.body;
  
  if (!messageId) {
    return res.status(400).json({ message: 'Укажите ID сообщения' });
  }
  
  if (!content && !image_url) {
    return res.status(400).json({ message: 'Укажите content или image_url для редактирования' });
  }

  const contentStr = content != null ? String(content) : '';
  if (contentStr.length > 65535) {
    return res.status(400).json({ message: 'Текст сообщения не более 65535 символов' });
  }
  if (image_url != null && String(image_url).length > 2048) {
    return res.status(400).json({ message: 'Ссылка на изображение не более 2048 символов' });
  }
  
  try {
    // Проверяем, существует ли сообщение и получаем информацию о нем
    const messageCheck = await pool.query(
      `SELECT 
        messages.id,
        messages.chat_id,
        messages.user_id,
        messages.content,
        messages.image_url,
        messages.message_type
      FROM messages
      WHERE messages.id = $1`,
      [messageId]
    );
    
    if (messageCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение не найдено' });
    }
    
    const message = messageCheck.rows[0];
    
    // Дополнительная проверка: пользователь должен быть участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [message.chat_id, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    // Проверяем права: только автор сообщения может его редактировать
    if (message.user_id.toString() !== userId.toString()) {
      return res.status(403).json({ 
        message: 'Вы можете редактировать только свои сообщения' 
      });
    }
    
    // Обновляем сообщение
    const updateFields = [];
    const updateValues = [];
    let paramIndex = 1;
    
    if (content !== undefined) {
      updateFields.push(`content = $${paramIndex++}`);
      updateValues.push(content);
    }
    
    if (image_url !== undefined) {
      updateFields.push(`image_url = $${paramIndex++}`);
      updateValues.push(image_url);
    }
    
    // Всегда обновляем edited_at
    updateFields.push(`edited_at = CURRENT_TIMESTAMP`);
    updateValues.push(messageId);
    
    const updateQuery = `
      UPDATE messages 
      SET ${updateFields.join(', ')}
      WHERE id = $${paramIndex}
      RETURNING id, chat_id, user_id, content, image_url, original_image_url, file_url, file_name, file_size, file_mime, message_type, created_at, edited_at
    `;
    
    const result = await pool.query(updateQuery, updateValues);
    const updatedMessage = result.rows[0];
    const senderDisplay = (await getSenderDisplayName(req.user.userId)) || req.user.email;

    // Отправляем обновленное сообщение через WebSocket всем участникам чата
    try {
      const clients = getWebSocketClients();
      const members = await pool.query(
        'SELECT user_id FROM chat_users WHERE chat_id = $1',
        [updatedMessage.chat_id]
      );
      
      const wsMessage = {
        type: 'message_edited',
        id: updatedMessage.id,
        chat_id: updatedMessage.chat_id.toString(),
        user_id: updatedMessage.user_id,
        content: updatedMessage.content,
        image_url: updatedMessage.image_url,
        original_image_url: updatedMessage.original_image_url,
        file_url: updatedMessage.file_url,
        file_name: updatedMessage.file_name,
        file_size: updatedMessage.file_size,
        file_mime: updatedMessage.file_mime,
        message_type: updatedMessage.message_type,
        created_at: updatedMessage.created_at,
        edited_at: updatedMessage.edited_at,
        sender_email: senderDisplay
      };
      
      members.rows.forEach(row => {
        const client = clients.get(row.user_id.toString());
        if (client && client.readyState === 1) {
          client.send(JSON.stringify(wsMessage));
        }
      });
    } catch (wsError) {
      console.error('Ошибка отправки через WebSocket:', wsError);
    }
    
    res.status(200).json({
      id: updatedMessage.id,
      chat_id: updatedMessage.chat_id,
      user_id: updatedMessage.user_id,
      content: updatedMessage.content,
      image_url: updatedMessage.image_url,
      original_image_url: updatedMessage.original_image_url,
      file_url: updatedMessage.file_url,
      file_name: updatedMessage.file_name,
      file_size: updatedMessage.file_size,
      file_mime: updatedMessage.file_mime,
      message_type: updatedMessage.message_type,
      created_at: updatedMessage.created_at,
      edited_at: updatedMessage.edited_at,
      sender_email: senderDisplay
    });
  } catch (error) {
    console.error('Ошибка редактирования сообщения:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Удаление одного сообщения
export const deleteMessage = async (req, res) => {
  const messageId = req.params.messageId;
  // userId берем из токена (безопасно)
  const userId = req.user.userId;

  if (!messageId) {
    return res.status(400).json({ message: 'Укажите ID сообщения' });
  }

  try {
    // Проверяем, существует ли сообщение и получаем информацию о нем, включая image_url
    const messageCheck = await pool.query(
      `SELECT 
        messages.id,
        messages.chat_id,
        messages.user_id,
        messages.content,
        messages.created_at,
        messages.image_url,
        messages.original_image_url,
        messages.file_url,
        messages.message_type
      FROM messages
      WHERE messages.id = $1`,
      [messageId]
    );

    if (messageCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение не найдено' });
    }

    const message = messageCheck.rows[0];
    const chatId = message.chat_id;

    // Проверяем, существует ли чат
    const chatCheck = await pool.query(
      'SELECT id FROM chats WHERE id = $1',
      [chatId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Чат не найден' });
    }

    // Проверяем права: только автор сообщения может его удалить
    const messageUserId = message.user_id.toString();
    const requestUserId = userId.toString();

    if (messageUserId !== requestUserId) {
      return res.status(403).json({ 
        message: 'Вы можете удалять только свои сообщения' 
      });
    }

    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ 
        message: 'Вы не являетесь участником этого чата' 
      });
    }

    // Удаляем изображения из Яндекс Облака, если они есть
    if (message.image_url) {
      try {
        await deleteImage(message.image_url);
        console.log('Compressed image deleted from Yandex Cloud:', message.image_url);
      } catch (deleteError) {
        console.error('Ошибка удаления сжатого изображения из облака:', deleteError);
        // Продолжаем удаление сообщения, даже если изображение не удалилось
      }
    }
    
    // ✅ Удаляем оригинальное изображение, если оно есть
    if (message.original_image_url) {
      try {
        await deleteImage(message.original_image_url);
        console.log('Original image deleted from Yandex Cloud:', message.original_image_url);
      } catch (deleteError) {
        console.error('Ошибка удаления оригинального изображения из облака:', deleteError);
        // Продолжаем удаление сообщения, даже если изображение не удалилось
      }
    }

    // ✅ Удаляем файл-attachment, если он есть
    if (message.file_url) {
      try {
        await deleteCloudFile(message.file_url);
        console.log('File deleted from Yandex Cloud:', message.file_url);
      } catch (deleteError) {
        console.error('Ошибка удаления файла из облака:', deleteError);
      }
    }

    // Удаляем сообщение
    await pool.query('DELETE FROM messages WHERE id = $1', [messageId]);

    // Отправляем уведомление через WebSocket всем участникам чата об удалении
    try {
      const clients = getWebSocketClients();
      const members = await pool.query(
        'SELECT user_id FROM chat_users WHERE chat_id = $1',
        [chatId]
      );

      const wsMessage = {
        type: 'message_deleted',
        message_id: messageId.toString(),
        chat_id: chatId.toString(),
        user_id: userId.toString(),
      };

      console.log('Sending WebSocket delete notification to chat:', chatId);
      console.log('Delete notification:', wsMessage);

      const wsMessageString = JSON.stringify(wsMessage);
      
      let sentCount = 0;
      members.rows.forEach(row => {
        const userIdStr = row.user_id.toString();
        const client = clients.get(userIdStr);
        if (client && client.readyState === 1) { // WebSocket.OPEN
          try {
            client.send(wsMessageString);
            sentCount++;
            console.log(`Delete notification sent to user ${userIdStr}`);
          } catch (sendError) {
            console.error(`Error sending delete notification to user ${userIdStr}:`, sendError);
          }
        }
      });
      
      console.log(`Delete notification sent to ${sentCount} out of ${members.rows.length} members`);
    } catch (wsError) {
      console.error('Ошибка отправки уведомления об удалении через WebSocket:', wsError);
      // Не прерываем выполнение, сообщение уже удалено из БД
    }

    res.status(200).json({ 
      message: 'Сообщение успешно удалено',
      messageId: messageId
    });

  } catch (error) {
    console.error('Ошибка удаления сообщения:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Очистка всех сообщений из чата
export const clearChat = async (req, res) => {
  const chatId = req.params.chatId;
  // userId берем из токена (безопасно)
  const userId = req.user.userId;

  if (!chatId) {
    return res.status(400).json({ message: 'Укажите ID чата' });
  }

  try {
    // Проверяем, существует ли чат
    const chatCheck = await pool.query(
      'SELECT id, created_by FROM chats WHERE id = $1',
      [chatId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Чат не найден' });
    }

    // Усиливаем безопасность: очищать чат может owner/admin (или создатель как fallback)
    const creatorId = chatCheck.rows[0].created_by?.toString();
    const roleCheck = await pool.query(
      'SELECT role FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    const role = (roleCheck.rows[0]?.role || '').toString().toLowerCase();
    const isOwnerOrAdmin = role === 'owner' || role === 'admin' || (creatorId && creatorId === userId.toString());
    if (!isOwnerOrAdmin) {
      return res.status(403).json({ message: 'Очистить чат может только owner/admin' });
    }

    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ 
        message: 'Вы не являетесь участником этого чата' 
      });
    }

    // Удаляем все сообщения из чата
    const deleteResult = await pool.query(
      'DELETE FROM messages WHERE chat_id = $1',
      [chatId]
    );

    res.status(200).json({ 
      message: 'Чат успешно очищен',
      deletedCount: deleteResult.rowCount
    });

  } catch (error) {
    console.error('Ошибка очистки чата:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// ✅ Отметить сообщение как прочитанное
export const markMessageAsRead = async (req, res) => {
  try {
    const messageId = req.params.messageId;
    const userId = req.user.userId;
    
    // Проверяем, существует ли сообщение
    const messageCheck = await pool.query(
      'SELECT chat_id FROM messages WHERE id = $1',
      [messageId]
    );
    
    if (messageCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение не найдено' });
    }
    
    const chatId = messageCheck.rows[0].chat_id;
    
    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }
    
    // Отмечаем сообщение как прочитанное (upsert)
    await pool.query(`
      INSERT INTO message_reads (message_id, user_id, read_at)
      VALUES ($1, $2, CURRENT_TIMESTAMP)
      ON CONFLICT (message_id, user_id) 
      DO UPDATE SET read_at = CURRENT_TIMESTAMP
    `, [messageId, userId]);
    
    // Отправляем событие через WebSocket отправителю сообщения
    const messageOwner = await pool.query(
      'SELECT user_id FROM messages WHERE id = $1',
      [messageId]
    );
    
    if (messageOwner.rows.length > 0) {
      const ownerId = messageOwner.rows[0].user_id.toString();
      const clients = getWebSocketClients();
      const client = clients.get(ownerId);
      
      if (client && client.readyState === 1) {
        client.send(JSON.stringify({
          type: 'message_read',
          message_id: messageId,
          read_by: userId,
          read_at: new Date().toISOString()
        }));
      }
    }
    
    res.status(200).json({ 
      success: true,
      message: 'Сообщение отмечено как прочитанное'
    });
  } catch (error) {
    console.error('Ошибка отметки сообщения как прочитанного:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// ✅ Отметить все сообщения в чате как прочитанные
export const markMessagesAsRead = async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const userId = req.user.userId;
    
    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }
    
    // Получаем все непрочитанные сообщения в чате
    const unreadMessages = await pool.query(`
      SELECT id, user_id 
      FROM messages 
      WHERE chat_id = $1 
      AND id NOT IN (
        SELECT message_id FROM message_reads WHERE user_id = $2
      )
    `, [chatId, userId]);
    
    // Отмечаем все сообщения как прочитанные
    if (unreadMessages.rows.length > 0) {
      const values = unreadMessages.rows.map((_, index) => 
        `($${index * 2 + 1}, $${index * 2 + 2}, CURRENT_TIMESTAMP)`
      ).join(', ');
      
      const params = unreadMessages.rows.flatMap(row => [row.id, userId]);
      
      await pool.query(`
        INSERT INTO message_reads (message_id, user_id, read_at)
        VALUES ${values}
        ON CONFLICT (message_id, user_id) 
        DO UPDATE SET read_at = CURRENT_TIMESTAMP
      `, params);
      
      // Отправляем события через WebSocket всем отправителям
      const clients = getWebSocketClients();
      const ownerIds = [...new Set(unreadMessages.rows.map(r => r.user_id.toString()))];
      
      ownerIds.forEach(ownerId => {
        const client = clients.get(ownerId);
        if (client && client.readyState === 1) {
          client.send(JSON.stringify({
            type: 'messages_read',
            chat_id: chatId,
            read_by: userId,
            read_count: unreadMessages.rows.filter(r => r.user_id.toString() === ownerId).length
          }));
        }
      });
    }
    
    res.status(200).json({ 
      success: true,
      read_count: unreadMessages.rows.length,
      message: 'Сообщения отмечены как прочитанные'
    });
  } catch (error) {
    console.error('Ошибка отметки сообщений как прочитанных:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// ✅ Пересылка сообщений
const forwardMessages = async (req, res, fromMessageId, toChatIds, userId) => {
  try {
    // Получаем оригинальное сообщение
    const originalMessage = await pool.query(`
      SELECT 
        messages.*,
        chats.id AS original_chat_id,
        chats.name AS original_chat_name
      FROM messages
      JOIN chats ON messages.chat_id = chats.id
      WHERE messages.id = $1
    `, [fromMessageId]);
    
    if (originalMessage.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение для пересылки не найдено' });
    }
    
    const original = originalMessage.rows[0];

    // ✅ Пользователь должен быть участником исходного чата (иначе можно переслать "чужое" сообщение по id)
    const sourceMemberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [original.original_chat_id, userId]
    );
    if (sourceMemberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником исходного чата' });
    }

    const forwardedMessages = [];
    
    // Пересылаем в каждый указанный чат
    for (const toChatId of toChatIds) {
      // Проверяем, является ли пользователь участником чата
      const memberCheck = await pool.query(
        'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
        [toChatId, userId]
      );
      
      if (memberCheck.rows.length === 0) {
        continue; // Пропускаем чаты, где пользователь не участник
      }
      
      // Создаем новое сообщение в целевом чате
      const result = await pool.query(`
        INSERT INTO messages (chat_id, user_id, content, image_url, original_image_url, message_type, delivered_at)
        VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)
        RETURNING id, chat_id, user_id, content, image_url, original_image_url, message_type, created_at, delivered_at
      `, [
        toChatId,
        userId,
        original.content || '',
        original.image_url,
        original.original_image_url,
        original.message_type || 'text'
      ]);
      
      const newMessage = result.rows[0];
      
      // Сохраняем информацию о пересылке
      await pool.query(`
        INSERT INTO message_forwards (message_id, original_chat_id, original_message_id, forwarded_by)
        VALUES ($1, $2, $3, $4)
      `, [newMessage.id, original.original_chat_id, fromMessageId, userId]);
      
      const senderDisplay = (await getSenderDisplayName(req.user.userId)) || req.user.email;
      const clients = getWebSocketClients();
      const members = await pool.query(
        'SELECT user_id FROM chat_users WHERE chat_id = $1',
        [toChatId]
      );
      
      const wsMessage = {
        id: newMessage.id,
        chat_id: newMessage.chat_id.toString(),
        user_id: newMessage.user_id,
        content: newMessage.content,
        image_url: newMessage.image_url,
        original_image_url: newMessage.original_image_url,
        message_type: newMessage.message_type,
        created_at: newMessage.created_at,
        delivered_at: newMessage.delivered_at,
        is_forwarded: true,
        original_chat_name: original.original_chat_name,
        sender_email: senderDisplay
      };
      
      members.rows.forEach(row => {
        const client = clients.get(row.user_id.toString());
        if (client && client.readyState === 1) {
          client.send(JSON.stringify(wsMessage));
        }
      });
      
      forwardedMessages.push({ ...newMessage, sender_email: senderDisplay });
    }
    
    res.status(201).json({
      success: true,
      forwarded_count: forwardedMessages.length,
      messages: forwardedMessages
    });
  } catch (error) {
    console.error('Ошибка пересылки сообщений:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// ✅ Закрепить сообщение
export const pinMessage = async (req, res) => {
  try {
    const messageId = req.params.messageId;
    const userId = req.user.userId;
    
    // Проверяем сообщение
    const messageCheck = await pool.query(
      'SELECT chat_id FROM messages WHERE id = $1',
      [messageId]
    );
    
    if (messageCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение не найдено' });
    }
    
    const chatId = messageCheck.rows[0].chat_id;
    
    // Проверяем права (только участник чата может закрепить)
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }
    
    // Проверяем лимит закрепленных сообщений (максимум 5)
    const pinnedCount = await pool.query(
      'SELECT COUNT(*) as count FROM pinned_messages WHERE chat_id = $1',
      [chatId]
    );
    
    if (parseInt(pinnedCount.rows[0].count) >= 5) {
      return res.status(400).json({ message: 'Максимум 5 закрепленных сообщений в чате' });
    }
    
    // Закрепляем сообщение
    await pool.query(`
      INSERT INTO pinned_messages (chat_id, message_id, pinned_by)
      VALUES ($1, $2, $3)
      ON CONFLICT (chat_id, message_id) DO NOTHING
    `, [chatId, messageId, userId]);
    
    res.status(200).json({ success: true, message: 'Сообщение закреплено' });
  } catch (error) {
    console.error('Ошибка закрепления сообщения:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// ✅ Открепить сообщение
export const unpinMessage = async (req, res) => {
  try {
    const messageId = req.params.messageId;
    const userId = req.user.userId;
    
    // Проверяем сообщение
    const messageCheck = await pool.query(
      'SELECT chat_id FROM messages WHERE id = $1',
      [messageId]
    );
    
    if (messageCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение не найдено' });
    }
    
    const chatId = messageCheck.rows[0].chat_id;

    // Доступ только для участников чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }
    
    // Удаляем закрепление
    await pool.query(
      'DELETE FROM pinned_messages WHERE chat_id = $1 AND message_id = $2',
      [chatId, messageId]
    );
    
    res.status(200).json({ success: true, message: 'Сообщение откреплено' });
  } catch (error) {
    console.error('Ошибка открепления сообщения:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// ✅ Добавить реакцию на сообщение
export const addReaction = async (req, res) => {
  try {
    const messageId = req.params.messageId;
    const userId = req.user.userId;
    
    // ✅ Проверяем, что body парсится правильно
    if (!req.body) {
      console.error('❌ req.body is null or undefined');
      return res.status(400).json({ message: 'Тело запроса пустое' });
    }
    
    const { reaction } = req.body;
    
    if (!reaction || reaction.length === 0) {
      console.error('❌ reaction is missing or empty:', reaction);
      return res.status(400).json({ message: 'Укажите реакцию (эмодзи)' });
    }

    // Ограничение на размер (защита от мусора в БД)
    if (String(reaction).length > 32) {
      return res.status(400).json({ message: 'Слишком длинная реакция' });
    }
    
    // Проверяем сообщение
    const messageCheck = await pool.query(
      'SELECT chat_id FROM messages WHERE id = $1',
      [messageId]
    );
    
    if (messageCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение не найдено' });
    }
    
    const chatId = messageCheck.rows[0].chat_id;

    // Доступ только для участников чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }
    
    // ✅ Проверяем существование таблицы перед запросом
    const tableCheck = await pool.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = 'message_reactions'
      );
    `);
    
    if (!tableCheck.rows[0].exists) {
      console.error('❌ Таблица message_reactions не существует!');
      return res.status(500).json({
        message: 'Таблица message_reactions не найдена. Примените миграцию базы данных.',
      });
    }
    
    if (process.env.NODE_ENV === 'development') {
      console.log('✅ Параметры запроса:', { messageId, userId, reaction });
    }
    
    // Добавляем или обновляем реакцию
    // Используем ON CONFLICT для обработки случая, когда реакция уже существует
    const result = await pool.query(`
      INSERT INTO message_reactions (message_id, user_id, reaction)
      VALUES ($1, $2, $3)
      ON CONFLICT (message_id, user_id, reaction) DO UPDATE SET created_at = CURRENT_TIMESTAMP
      RETURNING id, message_id, user_id, reaction, created_at
    `, [messageId, userId, reaction]);
    
    if (process.env.NODE_ENV === 'development') {
      console.log('✅ Реакция успешно добавлена:', result.rows[0]);
    }
    
    // Отправляем через WebSocket
    const clients = getWebSocketClients();
    const members = await pool.query(
      'SELECT user_id FROM chat_users WHERE chat_id = $1',
      [chatId]
    );
    
    const wsMessage = {
      type: 'reaction_added',
      message_id: messageId,
      reaction: reaction,
      user_id: userId,
      user_email: req.user.email,
    };
    
    members.rows.forEach(row => {
      const client = clients.get(row.user_id.toString());
      if (client && client.readyState === 1) {
        client.send(JSON.stringify(wsMessage));
      }
    });
    
    res.status(200).json({
      success: true,
      reaction: result.rows[0]
    });
  } catch (error) {
    console.error('Ошибка добавления реакции:', error);
    
    // ✅ Более детальная обработка ошибок (без утечки stack/message в ответ)
    if (error.code === '23505') { // Unique violation
      return res.status(409).json({ message: 'Реакция уже существует' });
    } else if (error.code === '23503') { // Foreign key violation
      return res.status(404).json({ message: 'Сообщение или пользователь не найдены' });
    } else if (error.code === '42P01') { // Table doesn't exist
      return res.status(500).json({
        message: 'Таблица message_reactions не найдена. Примените миграцию базы данных.',
      });
    }
    
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// ✅ Удалить реакцию
export const removeReaction = async (req, res) => {
  try {
    const messageId = req.params.messageId;
    const { reaction } = req.body;
    const userId = req.user.userId;

    if (!reaction || String(reaction).length === 0) {
      return res.status(400).json({ message: 'Укажите реакцию (эмодзи)' });
    }
    if (String(reaction).length > 32) {
      return res.status(400).json({ message: 'Слишком длинная реакция' });
    }

    // Проверяем сообщение и доступ к чату
    const messageCheck = await pool.query(
      'SELECT chat_id FROM messages WHERE id = $1',
      [messageId]
    );
    if (messageCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Сообщение не найдено' });
    }
    const chatId = messageCheck.rows[0].chat_id;

    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }
    
    await pool.query(
      'DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2 AND reaction = $3',
      [messageId, userId, reaction]
    );
    
    // Отправляем через WebSocket
    if (chatId) {
      const clients = getWebSocketClients();
      const members = await pool.query(
        'SELECT user_id FROM chat_users WHERE chat_id = $1',
        [chatId]
      );
      
      const wsMessage = {
        type: 'reaction_removed',
        message_id: messageId,
        reaction: reaction,
        user_id: userId,
      };
      
      members.rows.forEach(row => {
        const client = clients.get(row.user_id.toString());
        if (client && client.readyState === 1) {
          client.send(JSON.stringify(wsMessage));
        }
      });
    }
    
    res.status(200).json({ success: true, message: 'Реакция удалена' });
  } catch (error) {
    console.error('Ошибка удаления реакции:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// ✅ Получить закрепленные сообщения чата
export const getPinnedMessages = async (req, res) => {
  try {
    const chatId = req.params.chatId;
    const userId = req.user.userId;
    
    // Проверяем права
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }
    
    const result = await pool.query(`
      SELECT 
        messages.*,
        COALESCE(users.display_name, users.email) AS sender_email,
        pinned_messages.pinned_at
      FROM pinned_messages
      JOIN messages ON pinned_messages.message_id = messages.id
      JOIN users ON messages.user_id = users.id
      WHERE pinned_messages.chat_id = $1
      ORDER BY pinned_messages.pinned_at DESC
    `, [chatId]);
    
    res.status(200).json({
      messages: result.rows.map(row => ({
        id: row.id,
        chat_id: row.chat_id,
        user_id: row.user_id,
        content: row.content,
        image_url: row.image_url,
        message_type: row.message_type,
        created_at: row.created_at,
        sender_email: row.sender_email,
        is_pinned: true,
        pinned_at: row.pinned_at,
      }))
    });
  } catch (error) {
    console.error('Ошибка получения закрепленных сообщений:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Загрузка изображения
export const uploadImage = async (req, res) => {
  try {
    console.log('Upload image request received');
    console.log('Request files:', req.files);
    
    // Получаем сжатое изображение (обязательно)
    const compressedFile = req.files?.['image']?.[0];
    if (!compressedFile) {
      console.error('No compressed image in request');
      return res.status(400).json({ message: 'Изображение не загружено' });
    }

    // Получаем оригинальное изображение (опционально)
    const originalFile = req.files?.['original']?.[0];
    
    console.log('Files received:', {
      compressed: {
        originalname: compressedFile.originalname,
        size: compressedFile.size,
        mimetype: compressedFile.mimetype
      },
      original: originalFile ? {
        originalname: originalFile.originalname,
        size: originalFile.size,
        mimetype: originalFile.mimetype
      } : 'not provided'
    });

    // Загружаем сжатое изображение в Яндекс Облако
    const { imageUrl, fileName } = await uploadToCloud(compressedFile, 'images');
    
    let originalImageUrl = null;
    
    // Если есть оригинал, загружаем его отдельно
    if (originalFile) {
      try {
        // Используем то же имя файла, но в папке original
        const originalFileName = fileName.replace('image-', 'original-');
        const { imageUrl: originalUrl } = await uploadToCloud(originalFile, 'original');
        originalImageUrl = originalUrl;
        console.log('Original image uploaded successfully:', originalImageUrl);
      } catch (error) {
        console.error('Error uploading original image:', error);
        // Не прерываем загрузку, если оригинал не загрузился
      }
    }
    
    console.log('Image uploaded successfully to Yandex Cloud:', {
      filename: fileName,
      compressedSize: compressedFile.size,
      originalSize: originalFile?.size || 0,
      mimetype: compressedFile.mimetype,
      imageUrl: imageUrl,
      originalImageUrl: originalImageUrl
    });
    
    res.status(200).json({
      image_url: imageUrl,
      original_image_url: originalImageUrl, // ✅ Возвращаем URL оригинала, если есть
      filename: fileName
    });
  } catch (error) {
    console.error('Ошибка загрузки изображения:', error);
    res.status(500).json({ message: 'Ошибка загрузки изображения' });
  }
};

// Загрузка файла (attachment)
export const uploadFile = async (req, res) => {
  try {
    const file = req.file;
    if (!file) {
      return res.status(400).json({ message: 'Файл не загружен' });
    }

    const uploaded = await uploadFileToCloud(file, 'files');

    return res.status(200).json({
      file_url: uploaded.fileUrl,
      file_name: uploaded.originalName,
      file_size: uploaded.size,
      file_mime: uploaded.mime,
      stored_file_name: uploaded.storedFileName,
    });
  } catch (error) {
    console.error('Ошибка загрузки файла:', error);
    return res.status(500).json({ message: 'Ошибка загрузки файла' });
  }
};
