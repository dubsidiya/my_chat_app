import pool from '../db.js';
import { getWebSocketClients } from '../websocket/websocket.js';
import { getWebSocketClients } from '../websocket/websocket.js';
import { uploadImage as uploadImageMiddleware, uploadToCloud, deleteImage } from '../utils/uploadImage.js';

export const getMessages = async (req, res) => {
  const chatId = req.params.chatId;
  
  // Параметры пагинации
  const limit = parseInt(req.query.limit) || 50; // По умолчанию 50 сообщений
  const offset = parseInt(req.query.offset) || 0;
  const beforeMessageId = req.query.before; // ID сообщения, до которого загружать (для cursor-based)

  try {
    let result;
    let totalCountResult;

    if (beforeMessageId) {
      // Cursor-based pagination: загружаем сообщения до указанного ID (старые сообщения)
      // Загружаем на 1 больше, чтобы проверить, есть ли еще сообщения
      result = await pool.query(`
        SELECT 
          messages.id,
          messages.chat_id,
          messages.user_id,
          messages.content,
          messages.image_url,
          messages.message_type,
          messages.created_at,
          messages.delivered_at,
          messages.edited_at,
          messages.reply_to_message_id,
          users.email AS sender_email,
          pinned_messages.id IS NOT NULL AS is_pinned
        FROM messages
        JOIN users ON messages.user_id = users.id
        LEFT JOIN pinned_messages ON pinned_messages.message_id = messages.id AND pinned_messages.chat_id = $1
        WHERE messages.chat_id = $1 AND messages.id < $2
        ORDER BY messages.id DESC
        LIMIT $3
      `, [chatId, beforeMessageId, limit + 1]);
      
      // Проверяем, есть ли еще сообщения (если получили больше чем limit)
      const hasMoreMessages = result.rows.length > limit;
      
      // Берем только limit сообщений
      if (hasMoreMessages) {
        result.rows = result.rows.slice(0, limit);
      }
      
      // Получаем общее количество для информации
      totalCountResult = await pool.query(
        'SELECT COUNT(*) as total FROM messages WHERE chat_id = $1',
        [chatId]
      );
    } else {
      // Offset-based pagination: загружаем последние N сообщений
      // Сначала получаем общее количество сообщений
      totalCountResult = await pool.query(
        'SELECT COUNT(*) as total FROM messages WHERE chat_id = $1',
        [chatId]
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
          messages.message_type,
          messages.created_at,
          messages.delivered_at,
          messages.edited_at,
          messages.reply_to_message_id,
          users.email AS sender_email,
          pinned_messages.id IS NOT NULL AS is_pinned
        FROM messages
        JOIN users ON messages.user_id = users.id
        LEFT JOIN pinned_messages ON pinned_messages.message_id = messages.id AND pinned_messages.chat_id = $1
        WHERE messages.chat_id = $1
        ORDER BY messages.created_at ASC
        LIMIT $2 OFFSET $3
      `, [chatId, limit, actualOffset]);
    }
    
    const totalCount = parseInt(totalCountResult.rows[0].total);

    // Получаем текущего пользователя для проверки прочтения
    const currentUserId = req.user.userId;
    
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
            users.email AS sender_email
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
          users.email AS user_email
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
        sender_email: row.sender_email
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
          [chatId, minId]
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

export const sendMessage = async (req, res) => {
  // Приложение отправляет: { chat_id, content, image_url, reply_to_message_id, forward_from_message_id, forward_to_chat_ids }
  const { chat_id, content, image_url, original_image_url, reply_to_message_id, forward_from_message_id, forward_to_chat_ids } = req.body;
  
  // userId берем из токена (безопасно)
  const user_id = req.user.userId;

  if (!chat_id || (!content && !image_url)) {
    return res.status(400).json({ message: 'Укажите chat_id и content или image_url' });
  }
  
  // ✅ Если пересылка сообщений
  if (forward_from_message_id && forward_to_chat_ids && Array.isArray(forward_to_chat_ids)) {
    return await forwardMessages(req, res, forward_from_message_id, forward_to_chat_ids, user_id);
  }

  try {
    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chat_id, user_id]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    // Определяем тип сообщения
    let message_type = 'text';
    if (image_url && content) {
      message_type = 'text_image';
    } else if (image_url) {
      message_type = 'image';
    }

    // Используем user_id из токена (безопасно)
    const result = await pool.query(`
      INSERT INTO messages (chat_id, user_id, content, image_url, original_image_url, message_type, delivered_at, reply_to_message_id)
      VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP, $7)
      RETURNING id, chat_id, user_id, content, image_url, original_image_url, message_type, created_at, delivered_at, reply_to_message_id
    `, [chat_id, user_id, content || '', image_url || null, original_image_url || null, message_type, reply_to_message_id || null]);

    // Используем email из токена
    const senderEmail = req.user.email;

    const message = result.rows[0];
    
    // ✅ Получаем сообщение, на которое отвечают (если есть)
    let replyToMessage = null;
    if (message.reply_to_message_id) {
      const replyCheck = await pool.query(`
        SELECT 
          messages.id,
          messages.content,
          messages.image_url,
          messages.user_id,
          users.email AS sender_email
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
      sender_email: senderEmail
    };

    // Отправляем сообщение через WebSocket всем участникам чата
    try {
      const clients = getWebSocketClients();
      const members = await pool.query(
        'SELECT user_id FROM chat_users WHERE chat_id = $1',
        [chat_id]
      );

      const wsMessage = {
        id: message.id,
        chat_id: message.chat_id.toString(), // Убеждаемся, что это строка
        user_id: message.user_id,
        content: message.content,
        image_url: message.image_url,
        message_type: message.message_type,
        created_at: message.created_at,
        delivered_at: message.delivered_at,
        edited_at: null,
        is_read: false,
        read_at: null,
        sender_email: senderEmail
      };

      console.log('Sending WebSocket message to chat:', chat_id);
      console.log('Message:', wsMessage);
      console.log('Chat members:', members.rows.map(r => r.user_id));
      console.log('Connected clients:', Array.from(clients.keys()));

      const wsMessageString = JSON.stringify(wsMessage);
      
      let sentCount = 0;
      members.rows.forEach(row => {
        const userIdStr = row.user_id.toString();
        const client = clients.get(userIdStr);
        if (client && client.readyState === 1) { // WebSocket.OPEN
          try {
            client.send(wsMessageString);
            sentCount++;
            console.log(`Message sent to user ${userIdStr}`);
          } catch (sendError) {
            console.error(`Error sending to user ${userIdStr}:`, sendError);
          }
        } else {
          console.log(`User ${userIdStr} not connected or connection not open (readyState: ${client?.readyState})`);
        }
      });
      
      console.log(`WebSocket message sent to ${sentCount} out of ${members.rows.length} members`);
    } catch (wsError) {
      console.error('Ошибка отправки через WebSocket:', wsError);
      console.error('Stack:', wsError.stack);
      // Не прерываем выполнение, сообщение уже сохранено в БД
    }

    res.status(201).json(response);
  } catch (error) {
    console.error('Ошибка отправки сообщения:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
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
      RETURNING id, chat_id, user_id, content, image_url, message_type, created_at, edited_at
    `;
    
    const result = await pool.query(updateQuery, updateValues);
    const updatedMessage = result.rows[0];
    
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
        message_type: updatedMessage.message_type,
        created_at: updatedMessage.created_at,
        edited_at: updatedMessage.edited_at,
        sender_email: req.user.email
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
      message_type: updatedMessage.message_type,
      created_at: updatedMessage.created_at,
      edited_at: updatedMessage.edited_at,
      sender_email: req.user.email
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
      
      // Отправляем через WebSocket
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
        sender_email: req.user.email
      };
      
      members.rows.forEach(row => {
        const client = clients.get(row.user_id.toString());
        if (client && client.readyState === 1) {
          client.send(JSON.stringify(wsMessage));
        }
      });
      
      forwardedMessages.push(newMessage);
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
    const { reaction } = req.body; // Эмодзи реакции
    const userId = req.user.userId;
    
    console.log('addReaction called:', { messageId, reaction, userId, body: req.body });
    
    if (!reaction || reaction.length === 0) {
      return res.status(400).json({ message: 'Укажите реакцию (эмодзи)' });
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
    
    // Проверяем права
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }
    
    // Добавляем или обновляем реакцию
    // Используем ON CONFLICT для обработки случая, когда реакция уже существует
    const result = await pool.query(`
      INSERT INTO message_reactions (message_id, user_id, reaction)
      VALUES ($1, $2, $3)
      ON CONFLICT (message_id, user_id, reaction) DO UPDATE SET created_at = CURRENT_TIMESTAMP
      RETURNING id, message_id, user_id, reaction, created_at
    `, [messageId, userId, reaction]);
    
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
    console.error('Error details:', {
      message: error.message,
      stack: error.stack,
      code: error.code
    });
    
    // ✅ Более детальная обработка ошибок
    if (error.code === '23505') { // Unique violation
      return res.status(409).json({ message: 'Реакция уже существует' });
    } else if (error.code === '23503') { // Foreign key violation
      return res.status(404).json({ message: 'Сообщение или пользователь не найдены' });
    } else if (error.code === '42P01') { // Table doesn't exist
      return res.status(500).json({ 
        message: 'Таблица message_reactions не найдена. Примените миграцию базы данных.',
        error: 'Migration required'
      });
    }
    
    res.status(500).json({ 
      message: 'Ошибка сервера',
      error: error.message 
    });
  }
};

// ✅ Удалить реакцию
export const removeReaction = async (req, res) => {
  try {
    const messageId = req.params.messageId;
    const { reaction } = req.body;
    const userId = req.user.userId;
    
    await pool.query(
      'DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2 AND reaction = $3',
      [messageId, userId, reaction]
    );
    
    // Отправляем через WebSocket
    const messageCheck = await pool.query(
      'SELECT chat_id FROM messages WHERE id = $1',
      [messageId]
    );
    
    if (messageCheck.rows.length > 0) {
      const chatId = messageCheck.rows[0].chat_id;
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
        users.email AS sender_email,
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
    console.error('Error stack:', error.stack);
    res.status(500).json({ 
      message: 'Ошибка загрузки изображения',
      error: error.message 
    });
  }
};
