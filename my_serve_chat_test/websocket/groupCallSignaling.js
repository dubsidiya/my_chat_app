/**
 * Group voice call signaling (mesh, ≤4 participants).
 * Relays SDP/ICE between members; does not touch media.
 * Room/roster state remains process-local until the LiveKit phase. Only the
 * cross-kind user busy lease is shared, so mesh rooms are not multi-instance.
 */

import { sendIncomingCallPushToUser } from '../utils/pushNotifications.js';
import {
  realtimeRuntime,
  isRealtimeUnavailable,
} from '../realtime/index.js';

/** @typedef {{ userId: string, state: 'ringing'|'joined', joinedAt?: number, email?: string }} GroupParticipant */
/** @typedef {{ callId: string, chatId: string, hostId: string, createdAt: number, participants: Map<string, GroupParticipant> }} GroupCall */

const activeGroupCalls = new Map(); // callId -> GroupCall
const userGroupCallId = new Map(); // userId -> callId
const chatActiveGroupCallId = new Map(); // chatId -> callId
/** In-flight gcall_create (await DB) — leave can cancel before insert. */
const pendingGroupCreates = new Map(); // callId -> { userId: string, cancelled: boolean }
/** @type {Map<string, NodeJS.Timeout>} */
const pendingGroupDisconnectRelease = new Map();

const MAX_PARTICIPANTS = 4;
const CALL_TTL_MS = 5 * 60 * 1000;
export const LEGACY_GROUP_BUSY_KIND = 'legacy_group_mesh';
export const LIVEKIT_GROUP_BUSY_KIND = 'livekit_group';

function releaseGroupBusy(userId, callId, runtime = realtimeRuntime) {
  try {
    return runtime.registry
      .releaseBusy({
        userId,
        kind: LEGACY_GROUP_BUSY_KIND,
        ownerId: callId,
      })
      .catch(() => false);
  } catch {
    // Fail closed: the bounded Redis lease remains until it can expire.
    return Promise.resolve(false);
  }
}

function releaseGroupChatBusy(chatId, callId, runtime = realtimeRuntime) {
  try {
    return runtime.registry
      .releaseChatBusy({
        chatId,
        kind: LEGACY_GROUP_BUSY_KIND,
        ownerId: callId,
      })
      .catch(() => false);
  } catch {
    return Promise.resolve(false);
  }
}

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

function cleanupGroupCall(callId, runtime = realtimeRuntime) {
  const call = activeGroupCalls.get(callId);
  if (!call) return;
  activeGroupCalls.delete(callId);
  if (chatActiveGroupCallId.get(call.chatId) === callId) {
    chatActiveGroupCallId.delete(call.chatId);
  }
  const releases = [];
  releases.push(releaseGroupChatBusy(call.chatId, call.callId, runtime));
  for (const uid of participantIds(call)) {
    if (userGroupCallId.get(uid) === callId) {
      userGroupCallId.delete(uid);
    }
    releases.push(releaseGroupBusy(uid, callId, runtime));
  }
  return Promise.allSettled(releases);
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

function removeParticipant(call, userId, runtime = realtimeRuntime) {
  const uid = userId.toString();
  call.participants.delete(uid);
  if (userGroupCallId.get(uid) === call.callId) {
    userGroupCallId.delete(uid);
  }
  return releaseGroupBusy(uid, call.callId, runtime);
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

export function cleanupStaleGroupCallsForUser(
  userId,
  runtime = realtimeRuntime
) {
  const uid = userId?.toString();
  if (!uid) return Promise.resolve();
  const callId = userGroupCallId.get(uid);
  if (!callId) return Promise.resolve();
  const call = activeGroupCalls.get(callId);
  if (!call) {
    userGroupCallId.delete(uid);
    return Promise.resolve();
  }
  const age = Date.now() - call.createdAt;
  const me = call.participants.get(uid);
  if (me?.state === 'ringing' && age > runtime.config.ringingTtlMs) {
    const release = removeParticipant(call, uid, runtime);
    if (joinedIds(call).length === 0) {
      return Promise.allSettled([
        release,
        cleanupGroupCall(callId, runtime),
      ]);
    }
    return release;
  }
  return Promise.resolve();
}

/**
 * Снимает зависших ringing-участников со всех групповых звонков.
 * Иначе ignore invite держит userGroupCallId forever (пока online).
 */
export function sweepStaleGroupRinging(
  sendToUserSockets,
  runtime = realtimeRuntime
) {
  const now = Date.now();
  for (const [callId, call] of [...activeGroupCalls.entries()]) {
    void runtime.registry
      .acquireChatBusy({
        chatId: call.chatId,
        kind: LEGACY_GROUP_BUSY_KIND,
        ownerId: callId,
        instanceId: runtime.instanceId,
      })
      .catch(() => {});
    for (const uid of participantIds(call)) {
      void runtime.registry
        .acquireBusy({
          userId: uid,
          kind: LEGACY_GROUP_BUSY_KIND,
          ownerId: callId,
          instanceId: runtime.instanceId,
        })
        .catch(() => {});
    }
    const age = now - call.createdAt;
    if (age <= runtime.config.ringingTtlMs) continue;
    let removed = false;
    for (const [uid, p] of [...call.participants.entries()]) {
      if (p.state !== 'ringing') continue;
      removeParticipant(call, uid, runtime);
      removed = true;
      if (sendToUserSockets) {
        sendToUserSockets(uid, {
          type: 'gcall_ended',
          call_id: callId,
          chat_id: call.chatId,
          from_user_id: uid,
          reason: 'ringing_timeout',
          ts: new Date().toISOString(),
        });
      }
    }
    if (removed && sendToUserSockets) {
      broadcastJoined(
        call,
        {
          type: 'gcall_peer_left',
          call_id: callId,
          chat_id: call.chatId,
          reason: 'ringing_timeout',
          roster: rosterPayload(call),
          ts: new Date().toISOString(),
        },
        sendToUserSockets
      );
    }
    if (joinedIds(call).length === 0) {
      if (sendToUserSockets) {
        broadcastGroup(
          call,
          {
            type: 'gcall_ended',
            call_id: callId,
            chat_id: call.chatId,
            reason: 'empty',
            ts: new Date().toISOString(),
          },
          sendToUserSockets
        );
      }
      cleanupGroupCall(callId, runtime);
      continue;
    }
    // Solo host «никто не ответил» — только если никто кроме host никогда не joined.
    // Иначе после реального разговора + leave peer'а не убиваем оставшегося.
    if (
      joinedIds(call).length === 1 &&
      age > runtime.config.ringingTtlMs &&
      !call.hadGuestJoin
    ) {
      const hostId = joinedIds(call)[0];
      if (sendToUserSockets) {
        broadcastGroup(
          call,
          {
            type: 'gcall_ended',
            call_id: callId,
            chat_id: call.chatId,
            from_user_id: hostId,
            reason: 'no_answer',
            ts: new Date().toISOString(),
          },
          sendToUserSockets
        );
      }
      cleanupGroupCall(callId, runtime);
    }
  }
}

/**
 * When user has no WS connections left, drop group call membership after grace.
 */
export function scheduleReleaseGroupCallsForUser(
  userId,
  sendToUserSockets,
  isStillOffline,
  runtime = realtimeRuntime
) {
  const uid = userId?.toString();
  if (!uid) return;
  cancelPendingGroupCallRelease(uid);

  const callId = userGroupCallId.get(uid);
  const call = callId ? activeGroupCalls.get(callId) : null;
  if (!call) return;
  const me = call.participants.get(uid);
  if (!me) return;

  const graceMs =
    me.state === 'joined'
      ? runtime.config.disconnectGraceMs
      : runtime.config.ringingDisconnectGraceMs;

  const timer = setTimeout(() => {
    pendingGroupDisconnectRelease.delete(uid);
    if (typeof isStillOffline === 'function' && !isStillOffline()) {
      return;
    }
    releaseGroupCallsForUser(uid, sendToUserSockets, runtime);
  }, graceMs);
  pendingGroupDisconnectRelease.set(uid, timer);
}

export function cancelPendingGroupCallRelease(userId) {
  const uid = userId?.toString();
  if (!uid) return;
  const timer = pendingGroupDisconnectRelease.get(uid);
  if (!timer) return;
  clearTimeout(timer);
  pendingGroupDisconnectRelease.delete(uid);
}

/**
 * Immediate release of group call membership.
 */
export async function releaseGroupCallsForUser(
  userId,
  sendToUserSockets,
  runtime = realtimeRuntime
) {
  const uid = userId?.toString();
  if (!uid) return;
  cancelPendingGroupCallRelease(uid);
  const callId = userGroupCallId.get(uid);
  if (!callId) return;
  const call = activeGroupCalls.get(callId);
  if (!call) {
    userGroupCallId.delete(uid);
    return;
  }

  const wasHost = uid === call.hostId;
  await removeParticipant(call, uid, runtime);
  const base = {
    call_id: callId,
    chat_id: call.chatId,
    from_user_id: uid,
    ts: new Date().toISOString(),
  };
  // Сообщаем самому отвалившемуся (иначе ghost UI / sticky busy на клиенте).
  sendToUserSockets(uid, { type: 'gcall_ended', ...base, reason: 'disconnected' });
  broadcastGroup(call, { type: 'gcall_peer_left', ...base, roster: rosterPayload(call) }, sendToUserSockets);

  const remaining = joinedIds(call);
  if (remaining.length === 0 || wasHost || remaining.length === 1) {
    const reason = wasHost ? 'host_left' : 'empty';
    broadcastGroup(call, { type: 'gcall_ended', ...base, reason }, sendToUserSockets);
    await cleanupGroupCall(callId, runtime);
  }
}

/**
 * @returns {boolean} true if handled
 */
async function handleGroupCallSignalingInner(data, ctx) {
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
    runtime = realtimeRuntime,
  } = ctx;

  if (!callLimiter.allow(`gcall:${userId}`)) {
    // leave/reject/join/ice не режем — иначе sticky busy / ICE restart рвёт звонок.
    const critical =
      type === 'gcall_leave' ||
      type === 'gcall_reject' ||
      type === 'gcall_join' ||
      type === 'gcall_ice' ||
      type === 'gcall_ice_restart';
    if (!critical) {
      sendGcallError(sendToUserSockets, userId, {
        code: 'rate_limited',
        call_id: data?.call_id,
      });
      return true;
    }
  }

  sweepStaleGroupRinging(sendToUserSockets, runtime);

  const callId = (data.call_id ?? data.callId)?.toString()?.trim();
  const chatIdRaw = data.chat_id ?? data.chatId;

  if (type === 'gcall_create') {
    if (!callId || callId.length > 128) {
      sendGcallError(sendToUserSockets, userId, { code: 'invalid_call_id', chat_id: chatIdRaw });
      return true;
    }
    if (activeGroupCalls.has(callId)) {
      sendGcallError(sendToUserSockets, userId, { code: 'call_id_exists', call_id: callId });
      return true;
    }
    if (!chatIdRaw) {
      sendGcallError(sendToUserSockets, userId, { code: 'chat_id_required' });
      return true;
    }

    pendingGroupCreates.set(callId, { userId: userId.toString(), cancelled: false });
    const group = await resolveGroupChat(pool, chatIdRaw, userId);
    const pending = pendingGroupCreates.get(callId);
    if (!pending || pending.cancelled) {
      pendingGroupCreates.delete(callId);
      return true;
    }
    if (!group.ok) {
      pendingGroupCreates.delete(callId);
      sendGcallError(sendToUserSockets, userId, {
        code: group.error,
        chat_id: chatIdRaw,
        call_id: callId,
      });
      return true;
    }

    await cleanupStaleGroupCallsForUser(userId, runtime);
    if (pendingGroupCreates.get(callId)?.cancelled) {
      pendingGroupCreates.delete(callId);
      return true;
    }
    const hostBusy = await runtime.registry.acquireBusy({
      userId,
      kind: LEGACY_GROUP_BUSY_KIND,
      ownerId: callId,
      instanceId: runtime.instanceId,
    });
    if (!hostBusy.ok) {
      pendingGroupCreates.delete(callId);
      sendGcallError(sendToUserSockets, userId, {
        code: 'busy',
        chat_id: group.chatIdNum.toString(),
        call_id: callId,
      });
      return true;
    }

    const chatIdStr = group.chatIdNum.toString();
    const chatBusy = await runtime.registry.acquireChatBusy({
      chatId: chatIdStr,
      kind: LEGACY_GROUP_BUSY_KIND,
      ownerId: callId,
      instanceId: runtime.instanceId,
    });
    if (!chatBusy.ok) {
      pendingGroupCreates.delete(callId);
      await releaseGroupBusy(userId, callId, runtime);
      sendGcallError(sendToUserSockets, userId, {
        code: 'chat_call_active',
        chat_id: chatIdStr,
        call_id: chatBusy.busy?.ownerId || callId,
      });
      return true;
    }
    if (chatActiveGroupCallId.has(chatIdStr)) {
      pendingGroupCreates.delete(callId);
      await Promise.allSettled([
        releaseGroupBusy(userId, callId, runtime),
        releaseGroupChatBusy(chatIdStr, callId, runtime),
      ]);
      sendGcallError(sendToUserSockets, userId, {
        code: 'chat_call_active',
        chat_id: chatIdStr,
        call_id: chatActiveGroupCallId.get(chatIdStr),
      });
      return true;
    }

    if (pendingGroupCreates.get(callId)?.cancelled) {
      pendingGroupCreates.delete(callId);
      await Promise.allSettled([
        releaseGroupBusy(userId, callId, runtime),
        releaseGroupChatBusy(chatIdStr, callId, runtime),
      ]);
      return true;
    }

    const now = Date.now();
    /** @type {GroupCall} */
    const call = {
      callId,
      chatId: chatIdStr,
      hostId: userId.toString(),
      createdAt: now,
      hadGuestJoin: false,
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
    pendingGroupCreates.delete(callId);

    // Invite other members (ringing slots, capped by max).
    const others = group.memberIds.filter((id) => id !== userId.toString());
    for (const peerId of others) {
      if (call.participants.size >= MAX_PARTICIPANTS) break;
      // Как DM: сначала stale cleanup invitee, иначе ignored invite держит busy 75s.
      await cleanupStaleGroupCallsForUser(peerId, runtime);
      const peerBusy = await runtime.registry.acquireBusy({
        userId: peerId,
        kind: LEGACY_GROUP_BUSY_KIND,
        ownerId: callId,
        instanceId: runtime.instanceId,
      });
      if (!peerBusy.ok) continue;
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
            expiresAt: call.createdAt + runtime.config.ringingTtlMs,
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
      const pending = pendingGroupCreates.get(callId);
      if (pending && pending.userId === userId.toString()) {
        pending.cancelled = true;
      }
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
    await cleanupGroupCall(callId, runtime);
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
    if (userId.toString() !== call.hostId) {
      call.hadGuestJoin = true;
    }

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
    await removeParticipant(call, userId, runtime);
    broadcastGroup(
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
      await cleanupGroupCall(callId, runtime);
    }
    return true;
  }

  if (type === 'gcall_leave') {
    const leavingWasHost = userId.toString() === call.hostId;
    await removeParticipant(call, userId, runtime);
    broadcastGroup(
      call,
      {
        type: 'gcall_peer_left',
        ...base,
        roster: rosterPayload(call),
      },
      sendToUserSockets
    );
    const remaining = joinedIds(call);
    // Host ушёл или остался ≤1 joined — завершаем (не strand'им гостя + chat lock).
    if (remaining.length === 0 || leavingWasHost || remaining.length === 1) {
      const reason = leavingWasHost ? 'host_left' : 'empty';
      broadcastGroup(call, { type: 'gcall_ended', ...base, reason }, sendToUserSockets);
      await cleanupGroupCall(callId, runtime);
    }
    return true;
  }

  if (type === 'gcall_offer' || type === 'gcall_answer' || type === 'gcall_ice' || type === 'gcall_ice_restart') {
    if (me.state !== 'joined') return true;
    const toUserId = (data.to_user_id ?? data.toUserId)?.toString();
    if (!toUserId) return true;
    const peer = call.participants.get(toUserId);
    if (!peer || peer.state !== 'joined') return true;

    if (type === 'gcall_ice_restart') {
      sendToUserSockets(toUserId, {
        type: 'gcall_ice_restart',
        ...base,
        to_user_id: toUserId,
      });
      return true;
    }

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

export async function handleGroupCallSignaling(data, ctx) {
  const type = data?.type;
  if (!type || typeof type !== 'string' || !type.startsWith('gcall_')) {
    return false;
  }
  try {
    return await handleGroupCallSignalingInner(data, ctx);
  } catch (error) {
    if (!isRealtimeUnavailable(error)) throw error;
    const payload = JSON.stringify({
      type: 'gcall_error',
      code: 'signaling_unavailable',
      call_id: data?.call_id,
      ts: new Date().toISOString(),
    });
    if (ctx.ws?.readyState === 1) {
      try {
        ctx.ws.send(payload);
      } catch {}
    }
    ctx.runtime?.telemetry?.('mutation_failed_closed', {
      operation: type,
      reason: 'realtime_unavailable',
    });
    return true;
  }
}
