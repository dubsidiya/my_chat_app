import pool from '../db.js';
import { getWebSocketClients } from '../websocket/websocket.js';

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
          messages.created_at,
          users.email AS sender_email
        FROM messages
        JOIN users ON messages.user_id = users.id
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
          messages.created_at,
          users.email AS sender_email
        FROM messages
        JOIN users ON messages.user_id = users.id
        WHERE messages.chat_id = $1
        ORDER BY messages.created_at ASC
        LIMIT $2 OFFSET $3
      `, [chatId, limit, actualOffset]);
    }
    
    const totalCount = parseInt(totalCountResult.rows[0].total);

    // Форматируем в формат, который ожидает приложение
    const formattedMessages = result.rows.map(row => ({
      id: row.id,
      chat_id: row.chat_id,
      user_id: row.user_id,
      content: row.content,
      created_at: row.created_at,
      sender_email: row.sender_email
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
  // Приложение отправляет: { chat_id, content }
  const { chat_id, content } = req.body;
  
  // userId берем из токена (безопасно)
  const user_id = req.user.userId;

  if (!chat_id || !content) {
    return res.status(400).json({ message: 'Укажите chat_id и content' });
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

    // Используем user_id из токена (безопасно)
    const result = await pool.query(`
      INSERT INTO messages (chat_id, user_id, content)
      VALUES ($1, $2, $3)
      RETURNING id, chat_id, user_id, content, created_at
    `, [chat_id, user_id, content]);

    // Используем email из токена
    const senderEmail = req.user.email;

    const message = result.rows[0];
    
    const response = {
      id: message.id,
      chat_id: message.chat_id,
      user_id: message.user_id,
      content: message.content,
      created_at: message.created_at,
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
        created_at: message.created_at,
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

// Удаление одного сообщения
export const deleteMessage = async (req, res) => {
  const messageId = req.params.messageId;
  // userId берем из токена (безопасно)
  const userId = req.user.userId;

  if (!messageId) {
    return res.status(400).json({ message: 'Укажите ID сообщения' });
  }

  try {
    // Проверяем, существует ли сообщение и получаем информацию о нем
    const messageCheck = await pool.query(
      `SELECT 
        messages.id,
        messages.chat_id,
        messages.user_id,
        messages.content,
        messages.created_at
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
