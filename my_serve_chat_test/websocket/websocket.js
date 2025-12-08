import { WebSocketServer } from 'ws';
import pool from '../db.js';

const clients = new Map(); // userId -> ws

// Экспортируем функцию для получения клиентов
export function getWebSocketClients() {
  return clients;
}

export function setupWebSocket(server) {
  const wss = new WebSocketServer({ server });

  wss.on('connection', (ws, req) => {
    const userId = new URL(req.url, `http://${req.headers.host}`).searchParams.get('userId');
    if (!userId) return ws.close();

    clients.set(userId, ws);

    ws.on('message', async (message) => {
      try {
        const data = JSON.parse(message);
        if (data.type === 'send') {
          // Приложение может отправлять через WebSocket или через HTTP
          // Поддерживаем оба варианта
          const { chatId, chat_id, senderId, user_id, content, senderEmail } = data;
          
          // Используем user_id или senderId (для обратной совместимости)
          const userId = user_id || senderId;
          const chatIdFinal = chat_id || chatId;

          if (!userId || !chatIdFinal || !content) {
            return;
          }

          // Используем user_id (как в схеме БД) вместо sender_id
          const result = await pool.query(`
            INSERT INTO messages (chat_id, user_id, content)
            VALUES ($1, $2, $3)
            RETURNING id, chat_id, user_id, content, created_at
          `, [chatIdFinal, userId, content]);

          // Получаем email пользователя, если не передан
          let senderEmailFinal = senderEmail;
          if (!senderEmailFinal) {
            const userResult = await pool.query(
              'SELECT email FROM users WHERE id = $1',
              [userId]
            );
            senderEmailFinal = userResult.rows[0]?.email || '';
          }

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
