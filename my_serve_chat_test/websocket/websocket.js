import { WebSocketServer } from 'ws';
import pool from '../db.js';
import { verifyWebSocketToken } from '../middleware/auth.js';

const clients = new Map(); // userId -> ws

async function ensureChatMember(chatId, userId) {
  const chatIdNum = parseInt(chatId, 10);
  if (!Number.isFinite(chatIdNum)) return { ok: false, status: 400 };

  const memberCheck = await pool.query(
    'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
    [chatIdNum, userId]
  );
  if (memberCheck.rows.length === 0) return { ok: false, status: 403, chatIdNum };
  return { ok: true, chatIdNum };
}

async function broadcastToChat(chatIdNum, payload, { excludeUserId } = {}) {
  const members = await pool.query(
    'SELECT user_id FROM chat_users WHERE chat_id = $1',
    [chatIdNum]
  );

  const data = JSON.stringify(payload);
  members.rows.forEach((row) => {
    const memberId = row.user_id?.toString();
    if (!memberId) return;
    if (excludeUserId && memberId === excludeUserId.toString()) return;
    const client = clients.get(memberId);
    if (client && client.readyState === 1) {
      client.send(data);
    }
  });
}

// Экспортируем функцию для получения клиентов
export function getWebSocketClients() {
  return clients;
}

export function setupWebSocket(server) {
  // Лимит размера одного сообщения (64 KB) — защита от DoS
  const MAX_WS_PAYLOAD = 64 * 1024;
  const wss = new WebSocketServer({ server, maxPayload: MAX_WS_PAYLOAD });

  wss.on('connection', (ws, req) => {
    // Получаем токен:
    // 1) из Authorization header (предпочтительно для mobile/desktop)
    // 2) из query параметра token (fallback для web)
    let token = null;

    const authHeader = (req.headers['authorization'] || '').toString();
    if (authHeader.toLowerCase().startsWith('bearer ')) {
      token = authHeader.slice(7).trim();
    }

    if (!token) {
      const url = new URL(req.url, `http://${req.headers.host}`);
      token = url.searchParams.get('token');
    }
    
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
    ws.userId = userId;
    ws.userEmail = userEmail;
    ws.subscriptions = new Set(); // chatIds (string)

    ws.on('message', async (message) => {
      try {
        const data = JSON.parse(message);
        
        // ✅ Подписка на presence/typing конкретного чата
        if (data.type === 'subscribe') {
          const chatId = data.chat_id || data.chatId;
          if (!chatId) return;

          const membership = await ensureChatMember(chatId, userId);
          if (!membership.ok) return;
          const chatIdNum = membership.chatIdNum;

          ws.subscriptions.add(chatIdNum.toString());

          // Возвращаем текущее состояние "кто онлайн" в этом чате
          const members = await pool.query(
            'SELECT user_id FROM chat_users WHERE chat_id = $1',
            [chatIdNum]
          );
          const onlineUserIds = members.rows
            .map((r) => r.user_id?.toString())
            .filter((id) => id && clients.get(id)?.readyState === 1);

          ws.send(JSON.stringify({
            type: 'presence_state',
            chat_id: chatIdNum.toString(),
            online_user_ids: onlineUserIds,
            ts: new Date().toISOString(),
          }));

          // Сообщаем остальным участникам (у кого открыт этот чат), что пользователь онлайн
          await broadcastToChat(chatIdNum, {
            type: 'presence',
            chat_id: chatIdNum.toString(),
            user_id: userId,
            user_email: userEmail,
            status: 'online',
            ts: new Date().toISOString(),
          }, { excludeUserId: userId });

          return;
        }

        if (data.type === 'unsubscribe') {
          const chatId = data.chat_id || data.chatId;
          if (!chatId) return;
          const chatIdNum = parseInt(chatId, 10);
          if (!Number.isFinite(chatIdNum)) return;
          ws.subscriptions.delete(chatIdNum.toString());
          return;
        }

        // ✅ Индикатор "печатает"
        if (data.type === 'typing') {
          const chatId = data.chat_id || data.chatId;
          const isTyping = data.is_typing === true;
          if (!chatId) return;

          const membership = await ensureChatMember(chatId, userId);
          if (!membership.ok) return;
          const chatIdNum = membership.chatIdNum;

          await broadcastToChat(chatIdNum, {
            type: 'typing',
            chat_id: chatIdNum.toString(),
            user_id: userId,
            user_email: userEmail,
            is_typing: isTyping,
            ts: new Date().toISOString(),
          }, { excludeUserId: userId });

          return;
        }

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
          // Лимит длины текста сообщения (защита от DoS)
          const contentStr = String(content);
          if (contentStr.length > 65535) {
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
          `, [chatIdFinal, userId, contentStr]);

          // Используем email из токена
          const senderEmailFinal = userEmail;

          const row = result.rows[0];
          const fullMessage = {
            type: 'message',
            id: row.id,
            chat_id: String(row.chat_id),
            user_id: row.user_id,
            content: row.content != null ? String(row.content) : '',
            created_at: row.created_at instanceof Date ? row.created_at.toISOString() : String(row.created_at ?? ''),
            sender_email: senderEmailFinal || '',
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
      // Уведомляем чаты, на которые был подписан клиент, что он оффлайн
      try {
        const subs = ws.subscriptions ? Array.from(ws.subscriptions) : [];
        subs.forEach((chatIdStr) => {
          const chatIdNum = parseInt(chatIdStr, 10);
          if (!Number.isFinite(chatIdNum)) return;
          // best-effort, без await (close handler)
          broadcastToChat(chatIdNum, {
            type: 'presence',
            chat_id: chatIdNum.toString(),
            user_id: userId,
            user_email: userEmail,
            status: 'offline',
            ts: new Date().toISOString(),
          }, { excludeUserId: userId }).catch(() => {});
        });
      } catch (_) {}
      clients.delete(userId);
    });
  });

  console.log('✅ WebSocket сервер запущен');
}
