/**
 * WebRTC DM call coordinator.
 *
 * Validation and payload shaping stay here. Durable state, fencing, leases,
 * expiry and cross-instance delivery belong to the configured realtime runtime.
 */
import crypto from 'node:crypto';

import { realtimeRuntime, isRealtimeUnavailable } from '../realtime/index.js';
import {
  sendCallReconciliationPushToUser,
  sendIncomingCallPushToUser,
} from '../utils/pushNotifications.js';

function normalizeMediaType(raw) {
  const value = (raw ?? 'audio').toString().trim().toLowerCase();
  return value === 'video' ? 'video' : 'audio';
}

export function parseCallMediaUpdate(data, currentMediaType) {
  const rawMediaType = data?.media_type ?? data?.mediaType;
  let mediaType = currentMediaType;
  if (rawMediaType !== undefined) {
    if (typeof rawMediaType !== 'string') return { ok: false };
    const normalized = rawMediaType.trim().toLowerCase();
    if (normalized !== 'audio' && normalized !== 'video') {
      return { ok: false };
    }
    mediaType = normalized;
  }
  const hasCameraOff = Object.prototype.hasOwnProperty.call(
    data ?? {},
    'camera_off'
  );
  if (hasCameraOff && typeof data.camera_off !== 'boolean') {
    return { ok: false };
  }
  return {
    ok: true,
    mediaType,
    hasCameraOff,
    cameraOff: hasCameraOff ? data.camera_off : undefined,
  };
}

function isParticipant(call, userId) {
  const uid = userId?.toString();
  return uid && (call.callerId === uid || call.calleeId === uid);
}

function peerIdFor(call, userId) {
  return call.callerId === userId?.toString()
    ? call.calleeId
    : call.callerId;
}

function getWsConnId(ws) {
  return ws?.connId?.toString() || null;
}

function sendCurrent(ws, payload) {
  if (ws?.readyState !== 1) return false;
  try {
    ws.send(JSON.stringify(payload));
    return true;
  } catch {
    return false;
  }
}

function sendCallError(ws, payload) {
  sendCurrent(ws, {
    type: 'call_error',
    ...payload,
    ts: new Date().toISOString(),
  });
}

function statusPayload(status, extra = {}) {
  return {
    type: 'call_status',
    status: status.active ? status.state : 'none',
    ...status,
    ...extra,
    ts: new Date().toISOString(),
  };
}

async function resolveDmChat(pool, chatIdRaw, userId) {
  const chatIdNum = Number.parseInt(chatIdRaw, 10);
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

  const ids = members.rows
    .map((row) => row.user_id?.toString())
    .filter(Boolean);
  const peerId = ids.find((id) => id !== userId.toString());
  if (!peerId) {
    return { ok: false, status: 403, error: 'peer_not_found' };
  }
  return { ok: true, chatIdNum, peerId };
}

async function deliverToPeerMedia(runtime, call, fromUserId, payload) {
  const peerId = peerIdFor(call, fromUserId);
  const connId = call.media?.[peerId]?.connId;
  if (!connId) {
    runtime.telemetry?.('delivery_miss', {
      operation: payload?.type || 'call_signal',
      reason: 'peer_media_unbound',
    });
    return false;
  }
  return runtime.deliver(peerId, payload, { connId });
}

async function broadcastToCall(runtime, call, payload) {
  await Promise.all([
    runtime.deliver(call.callerId, payload),
    runtime.deliver(call.calleeId, payload),
  ]);
}

function basePayload(call, callId, userId) {
  return {
    call_id: callId,
    chat_id: call.chatId,
    from_user_id: userId.toString(),
    ts: new Date().toISOString(),
  };
}

async function pushInvite({
  pool,
  peerId,
  callId,
  chatId,
  userId,
  userEmail,
  mediaType,
  expiresAt,
  callKitUuid,
}) {
  let chatName = userEmail || 'Звонок';
  try {
    const nameRow = await pool.query('SELECT name FROM chats WHERE id = $1', [
      Number.parseInt(chatId, 10),
    ]);
    if (nameRow.rows[0]?.name) chatName = String(nameRow.rows[0].name);
  } catch {
    // Push is best-effort and must never block signaling.
  }
  try {
    await sendIncomingCallPushToUser(pool, peerId, {
      callId,
      chatId,
      chatName,
      fromUserId: userId.toString(),
      fromEmail: userEmail || '',
      mediaType,
      expiresAt,
      callKitUuid,
    });
  } catch (error) {
    if (process.env.NODE_ENV !== 'production') {
      console.warn('sendIncomingCallPushToUser failed:', error?.message || error);
    }
  }
}

async function reconcileAnsweredElsewhere({ pool, userId, call }) {
  try {
    await sendCallReconciliationPushToUser(pool, userId, {
      callId: call.callId,
      callKitUuid: call.callKitUuid,
      chatId: call.chatId,
      status: 'accepted',
      reason: 'answered_elsewhere',
    });
  } catch (error) {
    if (process.env.NODE_ENV !== 'production') {
      console.warn(
        'sendCallReconciliationPushToUser failed:',
        error?.code || error?.name || 'unknown'
      );
    }
  }
}

function validateCallContext(call, userId, chatIdRaw) {
  if (!isParticipant(call, userId)) return 'forbidden';
  if (chatIdRaw && call.chatId !== chatIdRaw.toString()) {
    return 'chat_mismatch';
  }
  return null;
}

async function handleCallSignalingInner(data, ctx) {
  const type = data?.type;
  const {
    userId,
    userEmail,
    pool,
    ws,
    callLimiter,
    runtime = realtimeRuntime,
  } = ctx;
  const registry = runtime.registry;
  const myConnId = getWsConnId(ws);

  const critical = new Set([
    'call_hangup',
    'call_reject',
    'call_accept',
    'call_ice',
    'call_ice_restart',
    'call_resume',
  ]);
  if (
    !critical.has(type) &&
    !callLimiter.allow(`call:${userId}`)
  ) {
    sendCallError(ws, {
      code: 'rate_limited',
      call_id: data?.call_id,
      operation: type,
    });
    return true;
  }

  const callId = (data.call_id ?? data.callId)?.toString()?.trim();
  const chatIdRaw = data.chat_id ?? data.chatId;
  const requestId =
    typeof data.request_id === 'string' && data.request_id.length <= 64
      ? data.request_id
      : undefined;

  if (type === 'call_status') {
    if (callId && callId.length > 128) {
      sendCallError(ws, { code: 'invalid_call_id' });
      return true;
    }
    const status = await registry.getStatus(userId, { callId });
    sendCurrent(ws, statusPayload(status, { request_id: requestId }));
    return true;
  }

  if (type === 'call_invite') {
    if (!callId || callId.length > 128) {
      sendCallError(ws, {
        code: 'invalid_call_id',
        chat_id: chatIdRaw,
      });
      return true;
    }
    if (!chatIdRaw) {
      sendCallError(ws, { code: 'chat_id_required' });
      return true;
    }

    const dm = await resolveDmChat(pool, chatIdRaw, userId);
    if (!dm.ok) {
      sendCallError(ws, {
        code: dm.error,
        chat_id: chatIdRaw,
        call_id: callId,
      });
      return true;
    }

    const mediaType = normalizeMediaType(data.media_type ?? data.mediaType);
    const callKitUuid = crypto.randomUUID();
    const created = await registry.createDmCall({
      callId,
      callKitUuid,
      chatId: dm.chatIdNum.toString(),
      callerId: userId.toString(),
      calleeId: dm.peerId,
      mediaType,
      callerConnId: myConnId,
    });
    if (!created.ok) {
      runtime.telemetry?.('call_conflict', {
        operation: 'invite',
        reason: created.code || 'busy',
      });
      if (created.code === 'busy' && created.busyUserId === dm.peerId) {
        await runtime.deliver(userId, {
          type: 'call_busy',
          call_id: callId,
          chat_id: dm.chatIdNum.toString(),
          ts: new Date().toISOString(),
        });
      } else {
        sendCallError(ws, {
          code: created.code || 'busy',
          chat_id: dm.chatIdNum.toString(),
          call_id: callId,
        });
      }
      return true;
    }

    const chatId = dm.chatIdNum.toString();
    runtime.telemetry?.('call_transition', {
      operation: 'invite',
      state: 'ringing',
    });
    await runtime.deliver(dm.peerId, {
      type: 'call_invite',
      call_id: callId,
      chat_id: chatId,
      from_user_id: userId.toString(),
      from_user_email: userEmail || '',
      media_type: mediaType,
      callkit_uuid: created.call?.callKitUuid || callKitUuid,
      ts: new Date().toISOString(),
    });
    void pushInvite({
      pool,
      peerId: dm.peerId,
      callId,
      chatId,
      userId,
      userEmail,
      mediaType,
      expiresAt: created.call?.expiresAt,
      callKitUuid: created.call?.callKitUuid || callKitUuid,
    });
    return true;
  }

  if (!callId) return true;
  if (callId.length > 128) {
    sendCallError(ws, { code: 'invalid_call_id' });
    return true;
  }

  if (type === 'call_resume') {
    const resumableCall = await registry.getCall(callId);
    if (!resumableCall) {
      sendCurrent(
        ws,
        statusPayload({ active: false }, { request_id: requestId })
      );
      return true;
    }
    const resumeContextError = validateCallContext(
      resumableCall,
      userId,
      chatIdRaw
    );
    if (resumeContextError) {
      sendCallError(ws, {
        code: resumeContextError,
        call_id: callId,
      });
      return true;
    }
    const resumed = await registry.resumeDmCall({
      callId,
      userId,
      connId: myConnId,
    });
    if (!resumed.ok) {
      runtime.telemetry?.('call_resume_conflict', {
        operation: 'resume',
        reason: resumed.code || 'unknown',
      });
      if (resumed.status?.active) {
        sendCurrent(
          ws,
          statusPayload(resumed.status, {
            resumed: false,
            media_owner: false,
            request_id: requestId,
          })
        );
      } else {
        sendCurrent(
          ws,
          statusPayload({ active: false }, { request_id: requestId })
        );
      }
      if (resumed.code !== 'call_not_found') {
        sendCallError(ws, { code: resumed.code, call_id: callId });
      }
      return true;
    }
    sendCurrent(
      ws,
      statusPayload(resumed.status, {
        resumed: resumed.resumed === true,
        media_owner: true,
        request_id: requestId,
      })
    );
    runtime.telemetry?.('call_resumed', {
      operation: 'resume',
      state: resumed.call?.state,
    });
    if (resumed.call?.state === 'accepted') {
      await deliverToPeerMedia(
        runtime,
        resumed.call,
        userId,
        {
          type: 'call_resume',
          ...basePayload(resumed.call, callId, userId),
        }
      );
    }
    return true;
  }

  const call = await registry.getCall(callId);
  if (!call) {
    if (type === 'call_hangup' || type === 'call_reject') return true;
    sendCallError(ws, {
      code: 'call_not_found',
      call_id: callId,
      chat_id: chatIdRaw?.toString(),
    });
    return true;
  }
  const contextError = validateCallContext(call, userId, chatIdRaw);
  if (contextError) {
    sendCallError(ws, { code: contextError, call_id: callId });
    return true;
  }
  const base = basePayload(call, callId, userId);

  if (type === 'call_accept') {
    const accepted = await registry.acceptDmCall({
      callId,
      userId,
      connId: myConnId,
    });
    if (!accepted.ok) {
      if (accepted.code === 'media_owned_elsewhere') {
        sendCurrent(ws, {
          type: 'call_answered_elsewhere',
          ...base,
        });
        return true;
      }
      sendCallError(ws, { code: accepted.code, call_id: callId });
      return true;
    }
    sendCurrent(ws, {
      type: 'call_accept_ack',
      ...base,
      callkit_uuid: accepted.call?.callKitUuid,
      already_accepted: accepted.alreadyAccepted === true,
    });
    if (!accepted.alreadyAccepted) {
      runtime.telemetry?.('call_transition', {
        operation: 'accept',
        state: 'accepted',
      });
      await deliverToPeerMedia(runtime, accepted.call, userId, {
        type: 'call_accept',
        ...base,
      });
      if (myConnId) {
        await runtime.deliver(
          userId,
          { type: 'call_answered_elsewhere', ...base },
          { excludeConnId: myConnId }
        );
      }
      // Data-only normal push lets background/offline sibling installations
      // dismiss the ringing notification. The accepting device may receive it
      // too; clients only reconcile notification UI and retain media ownership.
      void reconcileAnsweredElsewhere({
        pool,
        userId,
        call: accepted.call,
      });
    }
    return true;
  }

  if (type === 'call_reject') {
    const reason = (data.reason ?? 'declined').toString().slice(0, 64);
    const rejected = await registry.terminateDmCall({
      callId,
      userId,
      connId: myConnId,
      reason,
      ringingOnly: true,
    });
    if (rejected.ok) {
      runtime.telemetry?.('call_transition', {
        operation: 'reject',
        state: 'ended',
      });
      await broadcastToCall(runtime, rejected.call, {
        type: 'call_reject',
        ...base,
        reason,
      });
    }
    return true;
  }

  if (type === 'call_hangup') {
    const ended = await registry.terminateDmCall({
      callId,
      userId,
      connId: myConnId,
      reason: 'hangup',
    });
    if (ended.ok) {
      runtime.telemetry?.('call_transition', {
        operation: 'hangup',
        state: 'ended',
      });
      await broadcastToCall(runtime, ended.call, {
        type: 'call_hangup',
        ...base,
      });
    }
    return true;
  }

  if (type === 'call_media_update') {
    const update = parseCallMediaUpdate(data, call.mediaType);
    if (!update.ok) {
      sendCallError(ws, {
        code: 'invalid_media_update',
        call_id: callId,
      });
      return true;
    }
    const authorized = await registry.authorizeMedia({
      callId,
      userId,
      connId: myConnId,
      mediaType: update.mediaType,
    });
    if (!authorized.ok) return true;
    const payload = {
      type: 'call_media_update',
      ...base,
      media_type: update.mediaType,
      reason: (data.reason ?? '').toString().slice(0, 64),
    };
    if (update.hasCameraOff) payload.camera_off = update.cameraOff;
    await deliverToPeerMedia(runtime, authorized.call, userId, payload);
    return true;
  }

  if (type === 'call_ice_restart') {
    const authorized = await registry.authorizeMedia({
      callId,
      userId,
      connId: myConnId,
    });
    if (!authorized.ok) return true;
    await deliverToPeerMedia(runtime, authorized.call, userId, {
      type: 'call_ice_restart',
      ...base,
    });
    return true;
  }

  if (type === 'call_offer' || type === 'call_answer') {
    const sdp = data.sdp;
    if (
      !sdp ||
      typeof sdp !== 'object' ||
      typeof sdp.type !== 'string' ||
      typeof sdp.sdp !== 'string' ||
      sdp.sdp.length > 48_000
    ) {
      return true;
    }
    const authorized = await registry.authorizeMedia({
      callId,
      userId,
      connId: myConnId,
    });
    if (!authorized.ok) return true;
    await deliverToPeerMedia(runtime, authorized.call, userId, {
      type,
      ...base,
      sdp: { type: sdp.type, sdp: sdp.sdp },
    });
    return true;
  }

  if (type === 'call_ice') {
    const candidate = data.candidate;
    if (!candidate || typeof candidate !== 'object') return true;
    if (JSON.stringify(candidate).length > 16_000) return true;
    const authorized = await registry.authorizeMedia({
      callId,
      userId,
      connId: myConnId,
    });
    if (!authorized.ok) return true;
    await deliverToPeerMedia(runtime, authorized.call, userId, {
      type: 'call_ice',
      ...base,
      candidate,
    });
    return true;
  }

  return false;
}

/**
 * @returns {Promise<boolean>} true when a call_* message was handled
 */
export async function handleCallSignaling(data, ctx) {
  const type = data?.type;
  if (!type || typeof type !== 'string' || !type.startsWith('call_')) {
    return false;
  }
  try {
    return await handleCallSignalingInner(data, ctx);
  } catch (error) {
    if (isRealtimeUnavailable(error)) {
      sendCallError(ctx.ws, {
        code: 'signaling_unavailable',
        call_id: data?.call_id,
        operation: type,
      });
      ctx.runtime?.telemetry?.('mutation_failed_closed', {
        operation: type,
        reason: 'realtime_unavailable',
      });
      return true;
    }
    throw error;
  }
}

// Compatibility helpers for legacy callers while state lives in the registry.
export async function getUserDmCallId(userId, runtime = realtimeRuntime) {
  return runtime.registry.getUserDmCallId(userId);
}

export async function cleanupStaleCallsForUser(
  _userId,
  _send,
  runtime = realtimeRuntime
) {
  return runtime.registry.sweepExpired();
}

export async function sweepStaleDmRinging(
  _send,
  runtime = realtimeRuntime
) {
  return runtime.registry.sweepExpired();
}
