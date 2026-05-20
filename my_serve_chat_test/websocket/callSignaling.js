/**
 * WebRTC voice call signaling (1-on-1 DM chats only).
 * Relays SDP/ICE between two participants; does not touch media.
 */

import { sendIncomingCallPushToUser } from '../utils/pushNotifications.js';

const activeCalls = new Map(); // callId -> { chatId, callerId, calleeId, state }
const userActiveCallId = new Map(); // userId -> callId

const CALL_TTL_MS = 5 * 60 * 1000;
const RINGING_STALE_MS = 90 * 1000;

function cleanupCall(callId) {
  const call = activeCalls.get(callId);
  if (!call) return;
  activeCalls.delete(callId);
  if (userActiveCallId.get(call.callerId) === callId) {
    userActiveCallId.delete(call.callerId);
  }
  if (userActiveCallId.get(call.calleeId) === callId) {
    userActiveCallId.delete(call.calleeId);
  }
}

function isParticipant(call, userId) {
  const uid = userId?.toString();
  return uid && (call.callerId === uid || call.calleeId === uid);
}

function peerIdFor(call, userId) {
  const uid = userId?.toString();
  return call.callerId === uid ? call.calleeId : call.callerId;
}

async function resolveDmChat(pool, chatIdRaw, userId) {
  const chatIdNum = parseInt(chatIdRaw, 10);
  if (!Number.isFinite(chatIdNum)) {
    return { ok: false, status: 400, error: 'invalid_chat_id' };
  }

  const chatRow = await pool.query(
    'SELECT is_group FROM chats WHERE id = $1',
    [chatIdNum]
  );
  if (chatRow.rows.length === 0) {
    return { ok: false, status: 404, error: 'chat_not_found' };
  }
  if (chatRow.rows[0].is_group) {
    return { ok: false, status: 403, error: 'group_calls_not_supported' };
  }

  const memberCheck = await pool.query(
    'SELECT user_id FROM chat_users WHERE chat_id = $1 AND user_id = $2',
    [chatIdNum, userId]
  );
  if (memberCheck.rows.length === 0) {
    return { ok: false, status: 403, error: 'not_a_member' };
  }

  const members = await pool.query(
    'SELECT user_id FROM chat_users WHERE chat_id = $1',
    [chatIdNum]
  );
  if (members.rows.length !== 2) {
    return { ok: false, status: 403, error: 'not_dm_chat' };
  }

  const ids = members.rows.map((r) => r.user_id?.toString()).filter(Boolean);
  const peerId = ids.find((id) => id !== userId.toString());
  if (!peerId) {
    return { ok: false, status: 403, error: 'peer_not_found' };
  }

  return { ok: true, chatIdNum, peerId };
}

function sendCallError(sendToUserSockets, userId, payload) {
  sendToUserSockets(userId, {
    type: 'call_error',
    ...payload,
    ts: new Date().toISOString(),
  });
}

function relayToPeer(sendToUserSockets, call, fromUserId, payload) {
  const target = peerIdFor(call, fromUserId);
  sendToUserSockets(target, payload);
}

function cleanupStaleCallsForUser(userId) {
  const uid = userId?.toString();
  if (!uid) return;
  const callId = userActiveCallId.get(uid);
  if (!callId) return;
  const call = activeCalls.get(callId);
  if (!call) {
    userActiveCallId.delete(uid);
    return;
  }
  const age = Date.now() - call.createdAt;
  // TTL чистит ТОЛЬКО ringing-сессии. Принятый звонок может длиться долго;
  // его убирает либо явный call_hangup, либо releaseCallsForUser на disconnect.
  if (call.state === 'ringing' && age > RINGING_STALE_MS) {
    cleanupCall(callId);
    return;
  }
  if (call.state === 'ringing' && age > CALL_TTL_MS) {
    cleanupCall(callId);
  }
}

/**
 * When user has no WS connections left, drop server-side call locks.
 */
export function releaseCallsForUser(userId, sendToUserSockets) {
  const uid = userId?.toString();
  if (!uid) return;
  const callId = userActiveCallId.get(uid);
  if (!callId) return;
  const call = activeCalls.get(callId);
  if (!call) {
    userActiveCallId.delete(uid);
    return;
  }
  const peer = peerIdFor(call, uid);
  const base = {
    call_id: callId,
    chat_id: call.chatId,
    from_user_id: uid,
    ts: new Date().toISOString(),
  };
  if (sendToUserSockets && peer) {
    sendToUserSockets(peer, { type: 'call_hangup', ...base });
  }
  cleanupCall(callId);
}

/**
 * @param {object} data - parsed WS JSON
 * @param {{ userId: string, userEmail: string, pool: import('pg').Pool, sendToUserSockets: Function, callLimiter: { allow: (key: string) => boolean } }} ctx
 * @returns {boolean} true if handled (call-related message)
 */
export async function handleCallSignaling(data, ctx) {
  const type = data?.type;
  if (!type || typeof type !== 'string' || !type.startsWith('call_')) {
    return false;
  }

  const { userId, userEmail, pool, sendToUserSockets, callLimiter } = ctx;
  if (!callLimiter.allow(`call:${userId}`)) {
    return true;
  }

  const callId = (data.call_id ?? data.callId)?.toString()?.trim();
  const chatIdRaw = data.chat_id ?? data.chatId;

  if (type === 'call_invite') {
    if (!callId || callId.length > 128) {
      sendCallError(sendToUserSockets, userId, { code: 'invalid_call_id', chat_id: chatIdRaw });
      return true;
    }
    if (!chatIdRaw) {
      sendCallError(sendToUserSockets, userId, { code: 'chat_id_required' });
      return true;
    }

    const dm = await resolveDmChat(pool, chatIdRaw, userId);
    if (!dm.ok) {
      sendCallError(sendToUserSockets, userId, {
        code: dm.error,
        chat_id: chatIdRaw,
        call_id: callId,
      });
      return true;
    }

    cleanupStaleCallsForUser(userId);
    cleanupStaleCallsForUser(dm.peerId);

    if (userActiveCallId.has(userId.toString())) {
      sendCallError(sendToUserSockets, userId, {
        code: 'busy',
        chat_id: dm.chatIdNum.toString(),
        call_id: callId,
      });
      return true;
    }
    if (userActiveCallId.has(dm.peerId)) {
      sendToUserSockets(userId, {
        type: 'call_busy',
        call_id: callId,
        chat_id: dm.chatIdNum.toString(),
        ts: new Date().toISOString(),
      });
      return true;
    }

    const now = Date.now();
    activeCalls.set(callId, {
      chatId: dm.chatIdNum.toString(),
      callerId: userId.toString(),
      calleeId: dm.peerId,
      state: 'ringing',
      createdAt: now,
    });
    userActiveCallId.set(userId.toString(), callId);
    userActiveCallId.set(dm.peerId, callId);

    const chatIdStr = dm.chatIdNum.toString();
    sendToUserSockets(dm.peerId, {
      type: 'call_invite',
      call_id: callId,
      chat_id: chatIdStr,
      from_user_id: userId.toString(),
      from_user_email: userEmail || '',
      ts: new Date().toISOString(),
    });

    // FCM: дублируем приглашение push-ом (клиент дедуплирует с WS).
    // Если WS онлайн, но приложение в фоне — push всё равно полезен.
    // ВАЖНО: push отправляем fire-and-forget. Иначе медленный/упавший Firebase
    // блокирует обработчик WS на несколько секунд — следующее сообщение от
    // того же клиента (offer/ICE) подвисает.
    (async () => {
      let chatName = userEmail || 'Звонок';
      try {
        const nameRow = await pool.query('SELECT name FROM chats WHERE id = $1', [dm.chatIdNum]);
        if (nameRow.rows[0]?.name) {
          chatName = String(nameRow.rows[0].name);
        }
      } catch (_) {
        /* best-effort */
      }
      try {
        await sendIncomingCallPushToUser(pool, dm.peerId, {
          callId,
          chatId: chatIdStr,
          chatName,
          fromUserId: userId.toString(),
          fromEmail: userEmail || '',
        });
      } catch (err) {
        if (process.env.NODE_ENV !== 'production') {
          console.warn('sendIncomingCallPushToUser failed:', err?.message || err);
        }
      }
    })();

    return true;
  }

  if (!callId) {
    return true;
  }

  const call = activeCalls.get(callId);
  if (!call) {
    if (type === 'call_hangup' || type === 'call_reject') {
      return true;
    }
    sendCallError(sendToUserSockets, userId, {
      code: 'call_not_found',
      call_id: callId,
      chat_id: chatIdRaw?.toString(),
    });
    return true;
  }

  // TTL применяем только к ringing-инвайтам — длинный разговор не должен
  // обрываться через 5 минут из-за того, что прилетел очередной ICE-candidate.
  if (call.state === 'ringing' && Date.now() - call.createdAt > CALL_TTL_MS) {
    cleanupCall(callId);
    sendCallError(sendToUserSockets, userId, { code: 'call_expired', call_id: callId });
    return true;
  }

  if (!isParticipant(call, userId)) {
    sendCallError(sendToUserSockets, userId, { code: 'forbidden', call_id: callId });
    return true;
  }

  if (chatIdRaw && call.chatId !== chatIdRaw.toString()) {
    sendCallError(sendToUserSockets, userId, { code: 'chat_mismatch', call_id: callId });
    return true;
  }

  const base = {
    call_id: callId,
    chat_id: call.chatId,
    from_user_id: userId.toString(),
    ts: new Date().toISOString(),
  };

  if (type === 'call_accept') {
    if (call.state !== 'ringing') {
      return true;
    }
    if (userId.toString() !== call.calleeId) {
      sendCallError(sendToUserSockets, userId, { code: 'only_callee_can_accept', call_id: callId });
      return true;
    }
    call.state = 'accepted';
    relayToPeer(sendToUserSockets, call, userId, { type: 'call_accept', ...base });
    return true;
  }

  if (type === 'call_reject') {
    relayToPeer(sendToUserSockets, call, userId, {
      type: 'call_reject',
      ...base,
      reason: (data.reason ?? 'declined').toString().slice(0, 64),
    });
    cleanupCall(callId);
    return true;
  }

  if (type === 'call_hangup') {
    relayToPeer(sendToUserSockets, call, userId, { type: 'call_hangup', ...base });
    cleanupCall(callId);
    return true;
  }

  if (type === 'call_offer' || type === 'call_answer') {
    // Offer/answer допустимы только после call_accept (state=accepted).
    // Принять SDP в ringing — узкое окно гонок и потенциальный вектор подмены.
    if (call.state !== 'accepted') {
      return true;
    }
    const sdp = data.sdp;
    if (!sdp || typeof sdp !== 'object') {
      return true;
    }
    const sdpType = sdp.type;
    const sdpBody = sdp.sdp;
    if (typeof sdpType !== 'string' || typeof sdpBody !== 'string') {
      return true;
    }
    if (sdpBody.length > 48_000) {
      return true;
    }
    relayToPeer(sendToUserSockets, call, userId, {
      type,
      ...base,
      sdp: { type: sdpType, sdp: sdpBody },
    });
    return true;
  }

  if (type === 'call_ice') {
    const candidate = data.candidate;
    if (!candidate || typeof candidate !== 'object') {
      return true;
    }
    const candStr = JSON.stringify(candidate);
    if (candStr.length > 16_000) {
      return true;
    }
    relayToPeer(sendToUserSockets, call, userId, {
      type: 'call_ice',
      ...base,
      candidate,
    });
    return true;
  }

  return false;
}
