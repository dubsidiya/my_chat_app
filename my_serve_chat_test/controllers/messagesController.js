import pool from '../db.js';
import { getWebSocketClients } from '../websocket/websocket.js';

export const getMessages = async (req, res) => {
  const chatId = req.params.chatId;

  try {
    // Используем user_id (как в схеме БД) вместо sender_id
    const result = await pool.query(`
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
    `, [chatId]);

    // Форматируем в формат, который ожидает приложение
    const formattedMessages = result.rows.map(row => ({
      id: row.id,
      chat_id: row.chat_id,
      user_id: row.user_id,
      content: row.content,
      created_at: row.created_at,
      sender_email: row.sender_email
    }));

    res.json(formattedMessages);
  } catch (error) {
    console.error('Ошибка получения сообщений:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const sendMessage = async (req, res) => {
  // Приложение отправляет: { user_id, chat_id, content }
  const { user_id, chat_id, content } = req.body;

  if (!user_id || !chat_id || !content) {
    return res.status(400).json({ message: 'Укажите user_id, chat_id и content' });
  }

  try {
    // Используем user_id (как в схеме БД) вместо sender_id
    const result = await pool.query(`
      INSERT INTO messages (chat_id, user_id, content)
      VALUES ($1, $2, $3)
      RETURNING id, chat_id, user_id, content, created_at
    `, [chat_id, user_id, content]);

    const userResult = await pool.query(
      'SELECT email FROM users WHERE id = $1',
      [user_id]
    );

    const message = result.rows[0];
    const senderEmail = userResult.rows[0]?.email || '';
    
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

// Очистка всех сообщений из чата
export const clearChat = async (req, res) => {
  const chatId = req.params.chatId;
  const userId = req.body.userId || req.query.userId;

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

    // Если указан userId, проверяем, является ли он участником чата
    if (userId) {
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
