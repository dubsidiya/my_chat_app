import crypto from 'node:crypto';

import {
  getLiveKitGroupCallCoordinator,
  participantRoster,
} from '../services/calls/livekitGroupCallCoordinator.js';
import { isRealtimeUnavailable } from '../realtime/index.js';

function sendError(runtime, userId, code, data = {}) {
  return runtime.deliver(userId, {
    type: 'lkcall_error',
    code,
    call_id: data.callId,
    chat_id: data.chatId,
    ts: new Date().toISOString(),
  });
}

function validId(value, max = 128) {
  const result = value?.toString().trim();
  return result && result.length <= max ? result : null;
}

async function handleInner(data, ctx) {
  const type = data?.type;
  if (!type?.startsWith('lkcall_')) return false;
  const {
    userId,
    userEmail,
    callLimiter,
    runtime,
    ws,
    coordinator = getLiveKitGroupCallCoordinator(),
  } = ctx;
  const connId = ws?.connId?.toString() || null;
  const critical = new Set([
    'lkcall_join',
    'lkcall_reject',
    'lkcall_leave',
  ]);
  if (
    !callLimiter.allow(`lkcall:${userId}`) &&
    !critical.has(type)
  ) {
    await sendError(runtime, userId, 'rate_limited', {
      callId: data.call_id,
      chatId: data.chat_id,
    });
    return true;
  }

  if (type === 'lkcall_create') {
    const chatId = validId(data.chat_id ?? data.chatId, 32);
    if (!chatId) {
      await sendError(runtime, userId, 'invalid_chat_id');
      return true;
    }
    const group = await coordinator.resolveGroupChat(chatId, userId);
    if (!group.ok) {
      await sendError(runtime, userId, group.code, { chatId });
      return true;
    }
    const requestedMediaType =
      String(data.initial_media_type ?? data.media_type).toLowerCase() ===
      'video'
        ? 'video'
        : 'audio';
    let transport = coordinator.selectTransport({
      chatId: group.chatId,
      protocolVersion: data.protocol_version ?? data.protocolVersion,
      appVersion: data.app_version ?? data.appVersion,
    });
    if (
      transport === 'livekit' &&
      (await coordinator.hasKnownUnsupportedLiveKitClients(
        [
          ...group.members.filter(
            (member) => member.userId === String(userId)
          ),
          ...group.members.filter(
            (member) => member.userId !== String(userId)
          ),
        ]
          .slice(0, coordinator.config.maxParticipants)
          .map((member) => member.userId)
      ))
    ) {
      transport = 'mesh';
    }
    if (transport === 'mesh') {
      await runtime.deliver(userId, {
        type: 'lkcall_use_mesh',
        chat_id: group.chatId,
        chat_name: group.chatName,
        requested_media_type: requestedMediaType,
        reason: coordinator.config.enabled ? 'rollout' : 'feature_off',
        ts: new Date().toISOString(),
      });
      return true;
    }

    const created = await coordinator.createCall({
      chatId: group.chatId,
      hostId: userId,
      hostLabel: userEmail,
      requestedMediaType,
    });
    if (!created.ok) {
      await sendError(runtime, userId, created.code || 'create_failed', {
        chatId: group.chatId,
        callId: created.activeCallId,
      });
      return true;
    }
    const call = created.call;
    await runtime.deliver(userId, {
      type: 'lkcall_created',
      protocol_version: 2,
      provider: 'livekit',
      call_id: call.callId,
      callkit_uuid: call.callKitUuid,
      chat_id: call.chatId,
      chat_name: created.chatName,
      initial_media_type: call.mediaType,
      max_participants: coordinator.config.maxParticipants,
      expires_at: new Date(call.expiresAt).toISOString(),
      roster: participantRoster(call),
      ts: new Date().toISOString(),
    });
    return true;
  }

  const callId = validId(data.call_id ?? data.callId);
  if (!callId) {
    await sendError(runtime, userId, 'invalid_call_id');
    return true;
  }
  const call = await runtime.registry.getLiveKitGroupCall(callId);
  if (!call) {
    const ended =
      await runtime.registry.getLiveKitGroupCallTombstone(callId);
    await sendError(runtime, userId, ended ? 'call_ended' : 'call_not_found', {
      callId,
    });
    return true;
  }
  const chatId = validId(data.chat_id ?? data.chatId, 32);
  if (chatId && chatId !== String(call.chatId)) {
    await sendError(runtime, userId, 'chat_mismatch', { callId, chatId });
    return true;
  }

  if (type === 'lkcall_join') {
    const answerTicket = crypto.randomBytes(32).toString('base64url');
    const answerTokenHash = crypto
      .createHash('sha256')
      .update(answerTicket)
      .digest('base64url');
    const joined = await coordinator.joinCall({
      callId,
      userId,
      connId,
      answerTokenHash,
    });
    if (!joined.ok) {
      if (joined.code === 'media_owned_elsewhere') {
        await runtime.deliver(
          userId,
          {
            type: 'lkcall_answered_elsewhere',
            call_id: callId,
            callkit_uuid: call.callKitUuid,
            chat_id: call.chatId,
            ts: new Date().toISOString(),
          },
          connId ? { connId } : {}
        );
        return true;
      }
      await sendError(runtime, userId, joined.code, {
        callId,
        chatId: call.chatId,
      });
      return true;
    }
    await runtime.deliver(
      userId,
      {
        type: 'lkcall_joined',
        call_id: callId,
        callkit_uuid: joined.call.callKitUuid,
        chat_id: call.chatId,
        initial_media_type: joined.call.mediaType,
        answer_ticket: answerTicket,
        roster: participantRoster(joined.call),
        ts: new Date().toISOString(),
      },
      connId ? { connId } : {}
    );
    if (connId) {
      await runtime.deliver(
        userId,
        {
          type: 'lkcall_answered_elsewhere',
          call_id: callId,
          callkit_uuid: joined.call.callKitUuid,
          chat_id: call.chatId,
          ts: new Date().toISOString(),
        },
        { excludeConnId: connId }
      );
    }
    if (!joined.alreadyJoined) {
      void coordinator
        .reconcileAnsweredElsewhere(joined.call, userId)
        .catch(() => {});
    }
    await coordinator.broadcastStatus(joined.call, userId, 'joined');
    return true;
  }

  if (type === 'lkcall_reject') {
    const result = await coordinator.rejectCall({
      callId,
      userId,
      reason: data.reason,
    });
    if (!result.ok) {
      await sendError(runtime, userId, result.code, {
        callId,
        chatId: call.chatId,
      });
      return true;
    }
    await coordinator.broadcastStatus(
      result.call,
      userId,
      data.reason || 'declined'
    );
    return true;
  }

  if (type === 'lkcall_leave') {
    const result = await coordinator.leaveCall({
      callId,
      userId,
      reason: data.reason || 'left',
    });
    if (!result.ok) {
      await sendError(runtime, userId, result.code, {
        callId,
        chatId: call.chatId,
      });
    }
    return true;
  }

  return false;
}

export async function handleLiveKitGroupCallSignaling(data, ctx) {
  const type = data?.type;
  if (!type?.startsWith('lkcall_')) return false;
  try {
    return await handleInner(data, ctx);
  } catch (error) {
    if (!isRealtimeUnavailable(error)) throw error;
    await sendError(ctx.runtime, ctx.userId, 'signaling_unavailable', {
      callId: data.call_id,
      chatId: data.chat_id,
    }).catch(() => {});
    return true;
  }
}
