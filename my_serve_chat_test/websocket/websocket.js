import { WebSocketServer } from 'ws';
import pool from '../db.js';
import { verifyWebSocketToken } from '../middleware/auth.js';

const clients = new Map(); // userId -> ws

// Экспортируем функцию для получения клиентов
export function getWebSocketClients() {
  return clients;
}

export function setupWebSocket(server) {
  const wss = new WebSocketServer({ server });

  wss.on('connection', (ws, req) => {
    // Получаем токен из query параметров
    const url = new URL(req.url, `http://${req.headers.host}`);
    const token = url.searchParams.get('token');
    
    if (!token) {
      if (process.env.NODE_ENV === 'development') {
        console.log('WebSocket connection rejected: no token');
      }
      ws.close(1008, 'Токен отсутствует');
      return;
    }

    // Проверяем токен
    const decoded = verifyWebSocketToken(token);
    if (!decoded) {
      if (process.env.NODE_ENV === 'development') {
        console.log('WebSocket connection rejected: invalid token');
      }
      ws.close(1008, 'Недействительный токен');
      return;
    }

    const userId = decoded.userId.toString();
    const userEmail = decoded.email;

    if (process.env.NODE_ENV === 'development') {
      console.log(`WebSocket connected: userId=${userId}, email=${userEmail}`);
    }
    clients.set(userId, ws);

    ws.on('message', async (message) => {
      try {
        const data = JSON.parse(message);
        
        // ✅ Обработка события прочтения сообщения
        if (data.type === 'mark_read') {
          const messageId = data.message_id;
          const chatId = data.chat_id;
          
          if (!messageId || !chatId) {
            return;
          }
          
          // Проверяем, является ли пользователь участником чата
          const memberCheck = await pool.query(
            'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
            [chatId, userId]
          );
          
          if (memberCheck.rows.length === 0) {
            return;
          }
          
          // Отмечаем сообщение как прочитанное
          await pool.query(`
            INSERT INTO message_reads (message_id, user_id, read_at)
            VALUES ($1, $2, CURRENT_TIMESTAMP)
            ON CONFLICT (message_id, user_id) 
            DO UPDATE SET read_at = CURRENT_TIMESTAMP
          `, [messageId, userId]);
          
          // Отправляем событие отправителю сообщения
          const messageOwner = await pool.query(
            'SELECT user_id FROM messages WHERE id = $1',
            [messageId]
          );
          
          if (messageOwner.rows.length > 0) {
            const ownerId = messageOwner.rows[0].user_id.toString();
            const ownerClient = clients.get(ownerId);
            if (ownerClient && ownerClient.readyState === 1) {
              ownerClient.send(JSON.stringify({
                type: 'message_read',
                message_id: messageId,
                read_by: userId,
                read_at: new Date().toISOString()
              }));
            }
          }
          
          return;
        }
        
        if (data.type === 'send') {
          // Используем userId из токена (безопасно)
          const chatIdFinal = data.chat_id || data.chatId;
          const content = data.content;

          if (!chatIdFinal || !content) {
            return;
          }

          // Проверяем, является ли пользователь участником чата
          const memberCheck = await pool.query(
            'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
            [chatIdFinal, userId]
          );

          if (memberCheck.rows.length === 0) {
            if (process.env.NODE_ENV === 'development') {
              console.log(`User ${userId} tried to send message to chat ${chatIdFinal} without being a member`);
            }
            return;
          }

          // Используем user_id (как в схеме БД) вместо sender_id
          const result = await pool.query(`
            INSERT INTO messages (chat_id, user_id, content)
            VALUES ($1, $2, $3)
            RETURNING id, chat_id, user_id, content, created_at
          `, [chatIdFinal, userId, content]);

          // Используем email из токена
          const senderEmailFinal = userEmail;

          const fullMessage = {
            id: result.rows[0].id,
            chat_id: result.rows[0].chat_id,
            user_id: result.rows[0].user_id,
            content: result.rows[0].content,
            created_at: result.rows[0].created_at,
            sender_email: senderEmailFinal,
          };

          // Используем chat_users (как в схеме БД) вместо chat_members
          const members = await pool.query(
            'SELECT user_id FROM chat_users WHERE chat_id = $1',
            [chatIdFinal]
          );

          members.rows.forEach(row => {
            const client = clients.get(row.user_id.toString());
            if (client && client.readyState === 1) {
              client.send(JSON.stringify(fullMessage));
            }
          });
        }
      } catch (e) {
        console.error('Ошибка WebSocket:', e);
      }
    });

    ws.on('close', () => {
      clients.delete(userId);
    });
  });

  console.log('✅ WebSocket сервер запущен');
}
