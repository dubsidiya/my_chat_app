import { WebSocketServer } from 'ws';
import pool from '../db.js';
import { verifyWebSocketToken } from '../middleware/auth.js';
import { sanitizeMessageContent } from '../utils/sanitize.js';

const clients = new Map(); // userId -> Set<ws>

const WS_OPEN = 1;

function getUserSockets(userId) {
  const key = userId?.toString();
  if (!key) return null;
  return clients.get(key) ?? null;
}

function addClientSocket(userId, ws) {
  const key = userId?.toString();
  if (!key || !ws) return;
  let sockets = clients.get(key);
  if (!sockets) {
    sockets = new Set();
    clients.set(key, sockets);
  }
  sockets.add(ws);
}

function removeClientSocket(userId, ws) {
  const key = userId?.toString();
  if (!key) return;
  const sockets = clients.get(key);
  if (!sockets) return;
  sockets.delete(ws);
  if (sockets.size === 0) {
    clients.delete(key);
  }
}

function hasAnyOnlineSocket(userId) {
  const sockets = getUserSockets(userId);
  if (!sockets) return false;
  for (const ws of sockets) {
    if (ws?.readyState === WS_OPEN) return true;
  }
  return false;
}

function sendToUserSockets(userId, payload) {
  const sockets = getUserSockets(userId);
  if (!sockets || sockets.size === 0) return;
  const data = typeof payload === 'string' ? payload : JSON.stringify(payload);
  for (const ws of sockets) {
    if (ws?.readyState === WS_OPEN) {
      ws.send(data);
    }
  }
}

class WsRateLimiter {
  constructor(maxPerWindow, windowMs) {
    this._max = maxPerWindow;
    this._windowMs = windowMs;
    this._counts = new Map();
  }
  allow(key) {
    const now = Date.now();
    let entry = this._counts.get(key);
    if (!entry || now - entry.start > this._windowMs) {
      entry = { start: now, count: 0 };
    }
    entry.count++;
    this._counts.set(key, entry);
    return entry.count <= this._max;
  }
}

const sendLimiter = new WsRateLimiter(30, 10_000);
const typingLimiter = new WsRateLimiter(20, 10_000);
const markReadLimiter = new WsRateLimiter(60, 10_000);
const subscribeLimiter = new WsRateLimiter(30, 10_000);

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
    sendToUserSockets(memberId, data);
  });
}

// Экспортируем функцию для получения клиентов
export function getWebSocketClients() {
  return {
    get(userId) {
      const key = userId?.toString();
      if (!key) return undefined;
      const sockets = getUserSockets(key);
      if (!sockets || sockets.size === 0 || !hasAnyOnlineSocket(key)) return undefined;

      // Backward-compatible facade: old code expects one ws with readyState/send.
      return {
        readyState: WS_OPEN,
        send(data) {
          sendToUserSockets(key, data);
        },
      };
    },
  };
}

// E2EE: рассылка участникам чата (кроме excludeUserId) — для запроса ключа новым участником
export async function broadcastToChatMembers(chatIdNum, payload, { excludeUserId } = {}) {
  return broadcastToChat(chatIdNum, payload, { excludeUserId });
}

export function setupWebSocket(server) {
  // Лимит размера одного сообщения (64 KB) — защита от DoS
  const MAX_WS_PAYLOAD = 64 * 1024;
  const wss = new WebSocketServer({ server, maxPayload: MAX_WS_PAYLOAD });
  const allowQueryTokenFallback = process.env.ENABLE_WS_QUERY_TOKEN_FALLBACK !== 'false';
  const allowAccessTokenFallback = process.env.ENABLE_WS_ACCESS_TOKEN_FALLBACK !== 'false';

  wss.on('connection', async (ws, req) => {
    // Получаем токен:
    // 1) из Authorization header (предпочтительно для mobile/desktop)
    // 2) из query параметра token (fallback для web)
    let token = null;

    const authHeader = (req.headers['authorization'] || '').toString();
    if (authHeader.toLowerCase().startsWith('bearer ')) {
      token = authHeader.slice(7).trim();
    }

    if (!token) {
      const protocolHeader = (req.headers['sec-websocket-protocol'] || '').toString();
      if (protocolHeader) {
        const protocols = protocolHeader
          .split(',')
          .map((p) => p.trim())
          .filter(Boolean);
        const authProto = protocols.find((p) => p.startsWith('auth.'));
        if (authProto && authProto.length > 5) {
          token = authProto.slice(5);
        }
      }
    }

    if (!token) {
      const url = new URL(req.url, `http://${req.headers.host}`);
      const queryToken = url.searchParams.get('token');
      if (queryToken && allowQueryTokenFallback) {
        token = queryToken;
        if (process.env.NODE_ENV !== 'production') {
          console.warn('WebSocket auth: query token fallback used (legacy mode)');
        }
      }
    }
    
    if (!token) {
      if (process.env.NODE_ENV === 'development') {
        console.log('WebSocket connection rejected: no token');
      }
      ws.close(1008, 'Токен отсутствует');
      return;
    }

    const decoded = verifyWebSocketToken(token, { allowAccessTokenFallback });
    if (!decoded) {
      if (process.env.NODE_ENV === 'development') {
        console.log('WebSocket connection rejected: invalid token');
      }
      ws.close(1008, 'Недействительный токен');
      return;
    }

    try {
      const vRow = await pool.query('SELECT token_version FROM users WHERE id = $1', [decoded.userId]);
      if (vRow.rows.length === 0) {
        ws.close(1008, 'Пользователь не найден');
        return;
      }
      const dbVersion = vRow.rows[0].token_version ?? 0;
      const tokenVersion = decoded.tv ?? 0;
      if (tokenVersion !== dbVersion) {
        ws.close(1008, 'Сессия истекла');
        return;
      }
    } catch (err) {
      if (process.env.NODE_ENV === 'development') {
        console.error('WebSocket token_version check failed:', err.message);
      }
      ws.close(1011, 'Ошибка сервера');
      return;
    }

    const userId = decoded.userId.toString();
    const userEmail = decoded.email;
    const tokenVersion = decoded.tv ?? 0;

    if (process.env.NODE_ENV === 'development') {
      console.log(`WebSocket connected: userId=${userId}, email=${userEmail}`);
    }
    addClientSocket(userId, ws);
    ws.userId = userId;
    ws.userEmail = userEmail;
    ws.subscriptions = new Set();

    const recheckInterval = setInterval(async () => {
      try {
        const r = await pool.query('SELECT token_version FROM users WHERE id = $1', [decoded.userId]);
        if (r.rows.length === 0 || (r.rows[0].token_version ?? 0) !== tokenVersion) {
          ws.close(1008, 'Сессия истекла');
          clearInterval(recheckInterval);
        }
      } catch (_) {}
    }, 5 * 60 * 1000);

    ws.on('message', async (message) => {
      try {
        const data = JSON.parse(message);
        
        if (data.type === 'subscribe') {
          if (!subscribeLimiter.allow(userId)) return;
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
            .filter((id) => id && hasAnyOnlineSocket(id));

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

        if (data.type === 'typing') {
          if (!typingLimiter.allow(userId)) return;
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

        if (data.type === 'mark_read') {
          if (!markReadLimiter.allow(userId)) return;
          const messageId = data.message_id;
          const chatId = data.chat_id;
          
          if (!messageId || !chatId) {
            return;
          }

          const chatIdNum = parseInt(chatId, 10);
          const messageIdNum = parseInt(messageId, 10);
          if (!Number.isFinite(chatIdNum) || !Number.isFinite(messageIdNum)) {
            return;
          }
          
          // Проверяем, является ли пользователь участником чата
          const memberCheck = await pool.query(
            'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
            [chatIdNum, userId]
          );
          
          if (memberCheck.rows.length === 0) {
            return;
          }

          // message_id должен принадлежать тому же chat_id (защита от cross-chat read spoofing)
          const messageInChat = await pool.query(
            'SELECT user_id FROM messages WHERE id = $1 AND chat_id = $2',
            [messageIdNum, chatIdNum]
          );
          if (messageInChat.rows.length === 0) {
            return;
          }
          
          // Отмечаем сообщение как прочитанное
          await pool.query(`
            INSERT INTO message_reads (message_id, user_id, read_at)
            VALUES ($1, $2, CURRENT_TIMESTAMP)
            ON CONFLICT (message_id, user_id) 
            DO UPDATE SET read_at = CURRENT_TIMESTAMP
          `, [messageIdNum, userId]);
          
          // Отправляем событие отправителю сообщения
          const messageOwner = messageInChat;
          
          if (messageOwner.rows.length > 0) {
            const ownerId = messageOwner.rows[0].user_id.toString();
            sendToUserSockets(ownerId, {
              type: 'message_read',
              message_id: messageId,
              read_by: userId,
              read_at: new Date().toISOString(),
            });
          }
          
          return;
        }
        
        if (data.type === 'send') {
          if (!sendLimiter.allow(userId)) return;
          const chatIdFinal = data.chat_id || data.chatId;
          const content = data.content;

          if (!chatIdFinal || !content) {
            return;
          }
          const contentStr = sanitizeMessageContent(String(content));
          if (contentStr.length > 65535 || contentStr.length === 0) {
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
            sendToUserSockets(row.user_id?.toString(), fullMessage);
          });
        }
      } catch (e) {
        console.error('Ошибка WebSocket:', e);
      }
    });

    ws.on('close', () => {
      clearInterval(recheckInterval);
      removeClientSocket(userId, ws);
      if (hasAnyOnlineSocket(userId)) {
        return;
      }
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
    });
  });

  console.log('✅ WebSocket сервер запущен');
}
