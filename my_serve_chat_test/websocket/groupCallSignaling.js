/**
 * Group voice call signaling (mesh, ≤4 participants).
 * Relays SDP/ICE between members; does not touch media.
 */

import { sendIncomingCallPushToUser } from '../utils/pushNotifications.js';
import { getUserDmCallId } from './callSignaling.js';

/** @typedef {{ userId: string, state: 'ringing'|'joined', joinedAt?: number, email?: string }} GroupParticipant */
/** @typedef {{ callId: string, chatId: string, hostId: string, createdAt: number, participants: Map<string, GroupParticipant> }} GroupCall */

const activeGroupCalls = new Map(); // callId -> GroupCall
const userGroupCallId = new Map(); // userId -> callId
const chatActiveGroupCallId = new Map(); // chatId -> callId

const MAX_PARTICIPANTS = 4;
const CALL_TTL_MS = 5 * 60 * 1000;
const RINGING_STALE_MS = 90 * 1000;

/** @returns {string|null} */
export function getUserGroupCallId(userId) {
  const uid = userId?.toString();
  if (!uid) return null;
  return userGroupCallId.get(uid) || null;
}

function sendGcallError(sendToUserSockets, userId, payload) {
  sendToUserSockets(userId, {
    type: 'gcall_error',
    ...payload,
    ts: new Date().toISOString(),
  });
}

function participantIds(call) {
  return [...call.participants.keys()];
}

function joinedIds(call) {
  return [...call.participants.entries()]
    .filter(([, p]) => p.state === 'joined')
    .map(([id]) => id);
}

function rosterPayload(call) {
  return [...call.participants.values()].map((p) => ({
    user_id: p.userId,
    state: p.state,
    email: p.email || '',
  }));
}

function cleanupGroupCall(callId) {
  const call = activeGroupCalls.get(callId);
  if (!call) return;
  activeGroupCalls.delete(callId);
  if (chatActiveGroupCallId.get(call.chatId) === callId) {
    chatActiveGroupCallId.delete(call.chatId);
  }
  for (const uid of participantIds(call)) {
    if (userGroupCallId.get(uid) === callId) {
      userGroupCallId.delete(uid);
    }
  }
}

function broadcastGroup(call, payload, sendToUserSockets, { excludeUserId } = {}) {
  const exclude = excludeUserId?.toString();
  for (const uid of participantIds(call)) {
    if (exclude && uid === exclude) continue;
    sendToUserSockets(uid, payload);
  }
}

function broadcastJoined(call, payload, sendToUserSockets, { excludeUserId } = {}) {
  const exclude = excludeUserId?.toString();
  for (const uid of joinedIds(call)) {
    if (exclude && uid === exclude) continue;
    sendToUserSockets(uid, payload);
  }
}

function removeParticipant(call, userId) {
  const uid = userId.toString();
  call.participants.delete(uid);
  if (userGroupCallId.get(uid) === call.callId) {
    userGroupCallId.delete(uid);
  }
}

function isUserBusy(userId) {
  const uid = userId?.toString();
  if (!uid) return true;
  return Boolean(getUserDmCallId(uid) || userGroupCallId.get(uid));
}

async function resolveGroupChat(pool, chatIdRaw, userId) {
  const chatIdNum = parseInt(chatIdRaw, 10);
  if (!Number.isFinite(chatIdNum)) {
    return { ok: false, status: 400, error: 'invalid_chat_id' };
  }

  const chatRow = await pool.query(
    'SELECT is_group, name FROM chats WHERE id = $1',
    [chatIdNum]
  );
  if (chatRow.rows.length === 0) {
    return { ok: false, status: 404, error: 'chat_not_found' };
  }
  if (!chatRow.rows[0].is_group) {
    return { ok: false, status: 403, error: 'not_a_group_chat' };
  }

  const members = await pool.query(
    `SELECT cu.user_id, u.email
     FROM chat_users cu
     LEFT JOIN users u ON u.id = cu.user_id
     WHERE cu.chat_id = $1`,
    [chatIdNum]
  );
  if (members.rows.length === 0) {
    return { ok: false, status: 403, error: 'not_a_member' };
  }

  const memberIds = members.rows.map((r) => r.user_id?.toString()).filter(Boolean);
  if (!memberIds.includes(userId.toString())) {
    return { ok: false, status: 403, error: 'not_a_member' };
  }

  const emails = {};
  for (const row of members.rows) {
    const id = row.user_id?.toString();
    if (id) emails[id] = row.email || '';
  }

  return {
    ok: true,
    chatIdNum,
    chatName: chatRow.rows[0].name || 'Группа',
    memberIds,
    emails,
  };
}

function cleanupStaleGroupCallsForUser(userId) {
  const uid = userId?.toString();
  if (!uid) return;
  const callId = userGroupCallId.get(uid);
  if (!callId) return;
  const call = activeGroupCalls.get(callId);
  if (!call) {
    userGroupCallId.delete(uid);
    return;
  }
  const age = Date.now() - call.createdAt;
  const me = call.participants.get(uid);
  if (me?.state === 'ringing' && age > RINGING_STALE_MS) {
    removeParticipant(call, uid);
    if (joinedIds(call).length === 0) {
      cleanupGroupCall(callId);
    }
  }
}

/**
 * When user has no WS connections left, drop group call membership.
 */
export function releaseGroupCallsForUser(userId, sendToUserSockets) {
  const uid = userId?.toString();
  if (!uid) return;
  const callId = userGroupCallId.get(uid);
  if (!callId) return;
  const call = activeGroupCalls.get(callId);
  if (!call) {
    userGroupCallId.delete(uid);
    return;
  }

  removeParticipant(call, uid);
  const base = {
    call_id: callId,
    chat_id: call.chatId,
    from_user_id: uid,
    ts: new Date().toISOString(),
  };
  broadcastGroup(call, { type: 'gcall_peer_left', ...base, roster: rosterPayload(call) }, sendToUserSockets);

  if (joinedIds(call).length === 0) {
    broadcastGroup(call, { type: 'gcall_ended', ...base, reason: 'empty' }, sendToUserSockets);
    cleanupGroupCall(callId);
  }
}

/**
 * @returns {boolean} true if handled
 */
export async function handleGroupCallSignaling(data, ctx) {
  const type = data?.type;
  if (!type || typeof type !== 'string' || !type.startsWith('gcall_')) {
    return false;
  }

  const {
    userId,
    userEmail,
    pool,
    sendToUserSockets,
    callLimiter,
  } = ctx;

  if (!callLimiter.allow(`gcall:${userId}`)) {
    return true;
  }

  const callId = (data.call_id ?? data.callId)?.toString()?.trim();
  const chatIdRaw = data.chat_id ?? data.chatId;

  if (type === 'gcall_create') {
    if (!callId || callId.length > 128) {
      sendGcallError(sendToUserSockets, userId, { code: 'invalid_call_id', chat_id: chatIdRaw });
      return true;
    }
    if (!chatIdRaw) {
      sendGcallError(sendToUserSockets, userId, { code: 'chat_id_required' });
      return true;
    }

    const group = await resolveGroupChat(pool, chatIdRaw, userId);
    if (!group.ok) {
      sendGcallError(sendToUserSockets, userId, {
        code: group.error,
        chat_id: chatIdRaw,
        call_id: callId,
      });
      return true;
    }

    cleanupStaleGroupCallsForUser(userId);
    if (isUserBusy(userId)) {
      sendGcallError(sendToUserSockets, userId, {
        code: 'busy',
        chat_id: group.chatIdNum.toString(),
        call_id: callId,
      });
      return true;
    }

    const chatIdStr = group.chatIdNum.toString();
    if (chatActiveGroupCallId.has(chatIdStr)) {
      sendGcallError(sendToUserSockets, userId, {
        code: 'chat_call_active',
        chat_id: chatIdStr,
        call_id: chatActiveGroupCallId.get(chatIdStr),
      });
      return true;
    }

    const now = Date.now();
    /** @type {GroupCall} */
    const call = {
      callId,
      chatId: chatIdStr,
      hostId: userId.toString(),
      createdAt: now,
      participants: new Map(),
    };
    call.participants.set(userId.toString(), {
      userId: userId.toString(),
      state: 'joined',
      joinedAt: now,
      email: userEmail || group.emails[userId.toString()] || '',
    });

    activeGroupCalls.set(callId, call);
    chatActiveGroupCallId.set(chatIdStr, callId);
    userGroupCallId.set(userId.toString(), callId);

    // Invite other members (ringing slots, capped by max).
    const others = group.memberIds.filter((id) => id !== userId.toString());
    for (const peerId of others) {
      if (call.participants.size >= MAX_PARTICIPANTS) break;
      if (isUserBusy(peerId)) continue;
      call.participants.set(peerId, {
        userId: peerId,
        state: 'ringing',
        email: group.emails[peerId] || '',
      });
      userGroupCallId.set(peerId, callId);
    }

    const invitePayload = {
      type: 'gcall_invite',
      call_id: callId,
      chat_id: chatIdStr,
      chat_name: group.chatName,
      from_user_id: userId.toString(),
      from_user_email: userEmail || '',
      max_participants: MAX_PARTICIPANTS,
      roster: rosterPayload(call),
      ts: new Date().toISOString(),
    };

    for (const [pid, p] of call.participants) {
      if (p.state !== 'ringing') continue;
      sendToUserSockets(pid, invitePayload);
      (async () => {
        try {
          await sendIncomingCallPushToUser(pool, pid, {
            callId,
            chatId: chatIdStr,
            chatName: group.chatName,
            fromUserId: userId.toString(),
            fromEmail: userEmail || '',
            mediaType: 'audio',
            isGroup: true,
          });
        } catch (err) {
          if (process.env.NODE_ENV !== 'production') {
            console.warn('group call push failed:', err?.message || err);
          }
        }
      })();
    }

    sendToUserSockets(userId, {
      type: 'gcall_created',
      call_id: callId,
      chat_id: chatIdStr,
      chat_name: group.chatName,
      max_participants: MAX_PARTICIPANTS,
      roster: rosterPayload(call),
      ts: new Date().toISOString(),
    });

    return true;
  }

  if (!callId) {
    return true;
  }

  const call = activeGroupCalls.get(callId);
  if (!call) {
    if (type === 'gcall_leave' || type === 'gcall_reject') {
      return true;
    }
    sendGcallError(sendToUserSockets, userId, {
      code: 'call_not_found',
      call_id: callId,
      chat_id: chatIdRaw?.toString(),
    });
    return true;
  }

  if (Date.now() - call.createdAt > CALL_TTL_MS && joinedIds(call).length === 0) {
    cleanupGroupCall(callId);
    sendGcallError(sendToUserSockets, userId, { code: 'call_expired', call_id: callId });
    return true;
  }

  const me = call.participants.get(userId.toString());
  if (!me) {
    sendGcallError(sendToUserSockets, userId, { code: 'forbidden', call_id: callId });
    return true;
  }

  if (chatIdRaw && call.chatId !== chatIdRaw.toString()) {
    sendGcallError(sendToUserSockets, userId, { code: 'chat_mismatch', call_id: callId });
    return true;
  }

  const base = {
    call_id: callId,
    chat_id: call.chatId,
    from_user_id: userId.toString(),
    ts: new Date().toISOString(),
  };

  if (type === 'gcall_join') {
    if (me.state === 'joined') {
      sendToUserSockets(userId, {
        type: 'gcall_joined',
        ...base,
        roster: rosterPayload(call),
      });
      return true;
    }
    if (joinedIds(call).length >= MAX_PARTICIPANTS) {
      sendGcallError(sendToUserSockets, userId, { code: 'room_full', call_id: callId });
      return true;
    }
    me.state = 'joined';
    me.joinedAt = Date.now();
    me.email = userEmail || me.email || '';

    const joinedPayload = {
      type: 'gcall_peer_joined',
      ...base,
      user_id: userId.toString(),
      email: me.email,
      roster: rosterPayload(call),
    };
    broadcastJoined(call, joinedPayload, sendToUserSockets, { excludeUserId: userId });
    sendToUserSockets(userId, {
      type: 'gcall_joined',
      ...base,
      roster: rosterPayload(call),
    });
    return true;
  }

  if (type === 'gcall_reject') {
    removeParticipant(call, userId);
    broadcastJoined(
      call,
      {
        type: 'gcall_peer_left',
        ...base,
        reason: (data.reason ?? 'declined').toString().slice(0, 64),
        roster: rosterPayload(call),
      },
      sendToUserSockets
    );
    if (joinedIds(call).length === 0) {
      broadcastGroup(call, { type: 'gcall_ended', ...base, reason: 'empty' }, sendToUserSockets);
      cleanupGroupCall(callId);
    }
    return true;
  }

  if (type === 'gcall_leave') {
    removeParticipant(call, userId);
    broadcastGroup(
      call,
      {
        type: 'gcall_peer_left',
        ...base,
        roster: rosterPayload(call),
      },
      sendToUserSockets
    );
    if (joinedIds(call).length === 0) {
      broadcastGroup(call, { type: 'gcall_ended', ...base, reason: 'empty' }, sendToUserSockets);
      cleanupGroupCall(callId);
    }
    return true;
  }

  if (type === 'gcall_offer' || type === 'gcall_answer' || type === 'gcall_ice') {
    if (me.state !== 'joined') return true;
    const toUserId = (data.to_user_id ?? data.toUserId)?.toString();
    if (!toUserId) return true;
    const peer = call.participants.get(toUserId);
    if (!peer || peer.state !== 'joined') return true;

    if (type === 'gcall_offer' || type === 'gcall_answer') {
      const sdp = data.sdp;
      if (!sdp || typeof sdp !== 'object') return true;
      const sdpType = sdp.type;
      const sdpBody = sdp.sdp;
      if (typeof sdpType !== 'string' || typeof sdpBody !== 'string') return true;
      if (sdpBody.length > 48_000) return true;
      sendToUserSockets(toUserId, {
        type,
        ...base,
        to_user_id: toUserId,
        sdp: { type: sdpType, sdp: sdpBody },
      });
      return true;
    }

    const candidate = data.candidate;
    if (!candidate || typeof candidate !== 'object') return true;
    if (JSON.stringify(candidate).length > 16_000) return true;
    sendToUserSockets(toUserId, {
      type: 'gcall_ice',
      ...base,
      to_user_id: toUserId,
      candidate,
    });
    return true;
  }

  return false;
}
