import crypto from 'node:crypto';

import pool from '../../db.js';
import { realtimeRuntime } from '../../realtime/index.js';
import {
  sendCallReconciliationPushToUser,
  sendLiveKitGroupCallPushToUser,
} from '../../utils/pushNotifications.js';
import {
  buildLiveKitRoomName,
  compareAppVersions,
  loadLiveKitGroupConfig,
  selectGroupTransport,
} from './livekitGroupConfig.js';
import {
  createLiveKitRoomProvider,
  liveKitIdentityForUser,
  safeParticipantName,
  userIdFromLiveKitIdentity,
} from './livekitProvider.js';

function normalizeId(value) {
  const result = value?.toString().trim();
  return result || null;
}

function mediaType(value) {
  return String(value).toLowerCase() === 'video' ? 'video' : 'audio';
}

function participantRoster(call) {
  return (call?.participantOrder || [])
    .map((userId) => call.participants?.[userId])
    .filter(Boolean)
    .map((entry) => ({
      user_id: String(entry.userId),
      label: String(entry.label || '').slice(0, 80),
      state: entry.state,
    }));
}

export class LiveKitGroupCallCoordinator {
  constructor({
    config,
    provider,
    pool: database,
    runtime,
    pushSender = sendLiveKitGroupCallPushToUser,
  }) {
    this.config = config;
    this.provider = provider;
    this.pool = database;
    this.runtime = runtime;
    this.pushSender = pushSender;
  }

  selectTransport(input) {
    return selectGroupTransport(input, this.config);
  }

  async resolveGroupChat(chatIdRaw, userId) {
    const chatId = Number.parseInt(String(chatIdRaw), 10);
    if (!Number.isSafeInteger(chatId) || chatId <= 0) {
      return { ok: false, code: 'invalid_chat_id' };
    }
    const rows = await this.pool.query(
      `SELECT c.id AS chat_id, c.is_group, c.name AS chat_name,
              cu.user_id, COALESCE(NULLIF(TRIM(u.display_name), ''), u.email) AS label
         FROM chats c
         JOIN chat_users cu ON cu.chat_id = c.id
         JOIN users u ON u.id = cu.user_id
        WHERE c.id = $1
        ORDER BY cu.user_id`,
      [chatId]
    );
    if (rows.rows.length === 0) {
      return { ok: false, code: 'chat_not_found' };
    }
    if (!rows.rows[0].is_group) {
      return { ok: false, code: 'not_a_group_chat' };
    }
    const uid = String(userId);
    if (!rows.rows.some((row) => String(row.user_id) === uid)) {
      return { ok: false, code: 'not_a_member' };
    }
    return {
      ok: true,
      chatId: String(chatId),
      chatName: String(rows.rows[0].chat_name || 'Группа').slice(0, 120),
      members: rows.rows.map((row) => ({
        userId: String(row.user_id),
        label: safeParticipantName(row.label),
      })),
    };
  }

  async isCurrentMember(chatId, userId) {
    const result = await this.pool.query(
      `SELECT c.is_group
         FROM chats c
         JOIN chat_users cu ON cu.chat_id = c.id
        WHERE c.id = $1 AND cu.user_id = $2`,
      [chatId, userId]
    );
    return result.rows.length > 0 && result.rows[0].is_group === true;
  }

  async hasKnownUnsupportedLiveKitClients(memberIds) {
    const ids = [...new Set(memberIds.map((value) => Number(value)))]
      .filter((value) => Number.isSafeInteger(value) && value > 0);
    if (ids.length === 0) return false;
    try {
      const result = await this.pool.query(
        `SELECT user_id, capabilities, app_version
           FROM push_devices
          WHERE user_id = ANY($1::int[])
            AND disabled_at IS NULL`,
        [ids]
      );
      const byUser = new Map();
      for (const row of result.rows) {
        const uid = String(row.user_id);
        const entries = byUser.get(uid) || [];
        entries.push(row);
        byUser.set(uid, entries);
      }
      for (const entries of byUser.values()) {
        const supported = entries.some((entry) => {
          const protocol = Number(
            entry.capabilities?.livekitGroupProtocolVersion || 0
          );
          if (protocol >= 2) return true;
          if (!this.config.minAppVersion || !entry.app_version) return false;
          const comparison = compareAppVersions(
            entry.app_version,
            this.config.minAppVersion
          );
          return comparison != null && comparison >= 0;
        });
        if (!supported) return true;
      }
      return false;
    } catch (error) {
      if (error?.code === '42P01' || error?.code === '42703') return false;
      throw error;
    }
  }

  async createCall({
    chatId,
    hostId,
    hostLabel,
    requestedMediaType,
  }) {
    if (!this.config.enabled || !this.provider) {
      return { ok: false, code: 'livekit_unavailable' };
    }
    const group = await this.resolveGroupChat(chatId, hostId);
    if (!group.ok) return group;

    const host = String(hostId);
    const storedHostLabel = group.members.find(
      (entry) => entry.userId === host
    )?.label;
    const orderedMembers = [
      {
        userId: host,
        label: safeParticipantName(storedHostLabel || hostLabel),
      },
      ...group.members.filter((entry) => entry.userId !== host),
    ].slice(0, this.config.maxParticipants);
    const callId = crypto.randomUUID();
    const callKitUuid = crypto.randomUUID();
    const roomName = buildLiveKitRoomName(this.config, callId);
    const reserved = await this.runtime.registry.createLiveKitGroupCall({
      callId,
      callKitUuid,
      roomName,
      chatId: group.chatId,
      hostId: host,
      mediaType: mediaType(requestedMediaType),
      participants: orderedMembers,
      instanceId: this.runtime.instanceId,
    });
    if (!reserved.ok) return reserved;

    try {
      await this.provider.createRoom({
        roomName,
        maxParticipants: this.config.maxParticipants,
        emptyTimeoutSeconds: this.config.roomEmptyTimeoutSeconds,
      });
    } catch {
      await this.runtime.registry.finishLiveKitGroupCall({
        callId,
        reason: 'room_create_failed',
      });
      return { ok: false, code: 'room_create_failed' };
    }

    const call = reserved.call;
    const hostParticipant = call.participants?.[host];
    if (hostParticipant && (storedHostLabel || hostLabel)) {
      hostParticipant.label = safeParticipantName(
        storedHostLabel || hostLabel
      );
    }
    await this._sendInvitations(call, group.chatName);
    return { ok: true, call, chatName: group.chatName };
  }

  async _sendInvitations(call, chatName) {
    const host = call.participants?.[String(call.hostId)];
    const invite = {
      type: 'lkcall_invite',
      protocol_version: 2,
      provider: 'livekit',
      call_id: call.callId,
      callkit_uuid: call.callKitUuid,
      chat_id: call.chatId,
      chat_name: chatName,
      from_user_id: call.hostId,
      from_label: host?.label || 'Участник',
      initial_media_type: call.mediaType,
      max_participants: this.config.maxParticipants,
      expires_at: new Date(call.ringingExpiresAt).toISOString(),
      roster: participantRoster(call),
      ts: new Date().toISOString(),
    };
    for (const userId of call.participantOrder || []) {
      const participant = call.participants?.[userId];
      if (!participant || participant.state !== 'invited') continue;
      await this.runtime.deliver(userId, invite);
      void this.pushSender(
        this.pool,
        userId,
        {
          callId: call.callId,
          callKitUuid: call.callKitUuid,
          chatId: call.chatId,
          chatName,
          fromUserId: call.hostId,
          fromLabel: host?.label || 'Участник',
          mediaType: call.mediaType,
          expiresAt: call.ringingExpiresAt,
        }
      ).catch(() => {});
    }
  }

  async joinCall({ callId, userId, connId, answerTokenHash }) {
    const call = await this.runtime.registry.getLiveKitGroupCall(callId);
    if (!call) return { ok: false, code: 'call_not_found' };
    if (!(await this.isCurrentMember(call.chatId, userId))) {
      return { ok: false, code: 'not_a_member' };
    }
    return this.runtime.registry.joinLiveKitGroupCall({
      callId,
      userId,
      connId,
      answerTokenHash,
    });
  }

  async reconcileAnsweredElsewhere(call, userId) {
    if (!call?.callId || !userId) return;
    await sendCallReconciliationPushToUser(this.pool, userId, {
      callId: call.callId,
      callKitUuid: call.callKitUuid,
      chatId: call.chatId,
      status: 'accepted',
      reason: 'answered_elsewhere',
    });
  }

  async rejectCall({ callId, userId, reason }) {
    return this.runtime.registry.rejectLiveKitGroupCall({
      callId,
      userId,
      reason,
    });
  }

  async leaveCall({ callId, userId, reason = 'left', webhook = false }) {
    const result = await this.runtime.registry.leaveLiveKitGroupCall({
      callId,
      userId,
      reason,
      webhook,
    });
    if (result.ok && result.ended) {
      await this._deleteRoomBestEffort(result.call.roomName);
      await this.broadcastEnded(result.call);
    } else if (result.ok) {
      await this.broadcastStatus(result.call, userId, reason);
    }
    return result;
  }

  async finishCall(call, reason, { roomAlreadyFinished = false } = {}) {
    const result = await this.runtime.registry.finishLiveKitGroupCall({
      callId: call.callId,
      reason,
    });
    const ended = result.call || call;
    if (!roomAlreadyFinished) {
      await this._deleteRoomBestEffort(ended.roomName);
    }
    if (!result.alreadyEnded) await this.broadcastEnded(ended);
    return result;
  }

  async _deleteRoomBestEffort(roomName) {
    if (!roomName || !this.provider) return;
    try {
      await this.provider.deleteRoom(roomName);
    } catch {}
  }

  async broadcastStatus(call, changedUserId, reason = '') {
    if (!call) return;
    const payload = {
      type: 'lkcall_peer_status',
      call_id: call.callId,
      chat_id: call.chatId,
      user_id: String(changedUserId || ''),
      reason: String(reason || '').slice(0, 64),
      roster: participantRoster(call),
      ts: new Date().toISOString(),
    };
    await Promise.allSettled(
      (call.participantOrder || []).map((userId) =>
        this.runtime.deliver(userId, payload)
      )
    );
  }

  async broadcastEnded(call) {
    if (!call) return;
    const payload = {
      type: 'lkcall_ended',
      call_id: call.callId,
      chat_id: call.chatId,
      reason: call.reason || 'ended',
      ts: new Date().toISOString(),
    };
    await Promise.allSettled(
      (call.participantOrder || []).map((userId) =>
        this.runtime.deliver(userId, payload)
      )
    );
  }

  async handleSweptCall(call) {
    await this._deleteRoomBestEffort(call.roomName);
  }

  async handleMembershipRemoved(chatId, userId) {
    const call =
      await this.runtime.registry.getLiveKitGroupCallForChat(chatId);
    const uid = String(userId);
    if (!call?.participants?.[uid]) return { ok: true, active: false };
    try {
      await this.provider?.removeParticipant(
        call.roomName,
        liveKitIdentityForUser(uid)
      );
    } catch {}
    if (uid === String(call.hostId)) {
      return this.finishCall(call, 'host_membership_removed');
    }
    return this.leaveCall({
      callId: call.callId,
      userId: uid,
      reason: 'membership_removed',
    });
  }

  async handleWebhook(event) {
    const eventId =
      normalizeId(event?.id) ||
      crypto
        .createHash('sha256')
        .update(JSON.stringify(event || {}))
        .digest('base64url');
    if (
      !(await this.runtime.registry.claimLiveKitWebhookEvent(
        eventId,
        this.runtime.config.liveKitGroupCallTtlMs +
          this.runtime.config.tombstoneTtlMs
      ))
    ) {
      return { ok: true, duplicate: true };
    }
    const roomName = normalizeId(event?.room?.name);
    if (!roomName) return { ok: true, ignored: true };
    const call =
      await this.runtime.registry.getLiveKitGroupCallByRoom(roomName);
    if (!call) return { ok: true, ignored: true };
    const type = String(event?.event || '');
    if (type === 'room_finished') {
      await this.finishCall(call, 'room_finished', {
        roomAlreadyFinished: true,
      });
      return { ok: true };
    }

    const userId = userIdFromLiveKitIdentity(event?.participant?.identity);
    if (!userId || !call.participants?.[userId]) {
      return { ok: true, ignored: true };
    }
    if (type === 'participant_joined') {
      if (!(await this.isCurrentMember(call.chatId, userId))) {
        try {
          await this.provider?.removeParticipant(
            roomName,
            liveKitIdentityForUser(userId)
          );
        } catch {}
        await this.leaveCall({
          callId: call.callId,
          userId,
          reason: 'membership_revoked',
        });
        return { ok: true, removed: true };
      }
      const joined = await this.runtime.registry.joinLiveKitGroupCall({
        callId: call.callId,
        userId,
      });
      if (joined.ok) await this.broadcastStatus(joined.call, userId, 'joined');
      return { ok: true };
    }
    if (
      type === 'participant_left' ||
      type === 'participant_connection_aborted'
    ) {
      await this.leaveCall({
        callId: call.callId,
        userId,
        reason: type,
        webhook: true,
      });
      return { ok: true };
    }
    return { ok: true, ignored: true };
  }
}

let defaultCoordinator = null;
let coordinatorOverride = null;

export function createLiveKitGroupCallCoordinator({
  env = process.env,
  config = loadLiveKitGroupConfig(env),
  provider = createLiveKitRoomProvider(config),
  pool: database = pool,
  runtime = realtimeRuntime,
  pushSender,
} = {}) {
  return new LiveKitGroupCallCoordinator({
    config,
    provider,
    pool: database,
    runtime,
    ...(pushSender ? { pushSender } : {}),
  });
}

export function getLiveKitGroupCallCoordinator() {
  if (coordinatorOverride) return coordinatorOverride;
  defaultCoordinator ??= createLiveKitGroupCallCoordinator();
  return defaultCoordinator;
}

export function setLiveKitGroupCallCoordinatorForTests(value) {
  coordinatorOverride = value || null;
  defaultCoordinator = null;
}

export { participantRoster };
