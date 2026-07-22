import crypto from 'node:crypto';

function clone(value) {
  return value == null ? value : structuredClone(value);
}

function normalizeId(value) {
  const id = value?.toString().trim();
  return id || null;
}

function participant(call, userId) {
  const uid = normalizeId(userId);
  return uid && (call.callerId === uid || call.calleeId === uid);
}

function mediaBinding(call, userId) {
  return call.media?.[normalizeId(userId)] || null;
}

function groupParticipant(call, userId) {
  return call?.participants?.[normalizeId(userId)] || null;
}

export function publicCallStatus(call, userId) {
  if (!call || !participant(call, userId)) return { active: false };
  const uid = normalizeId(userId);
  return {
    active: true,
    call_id: call.callId,
    callkit_uuid: call.callKitUuid,
    chat_id: call.chatId,
    state: call.state,
    role: call.callerId === uid ? 'caller' : 'callee',
    media_type: call.mediaType,
    created_at: new Date(call.createdAt).toISOString(),
    updated_at: new Date(call.updatedAt).toISOString(),
    expires_at: new Date(call.expiresAt).toISOString(),
    revision: call.revision,
  };
}

export function publicLiveKitGroupStatus(call, userId) {
  const uid = normalizeId(userId);
  const me = groupParticipant(call, uid);
  if (!call || !uid || !me || ['declined', 'left', 'timed_out'].includes(me.state)) {
    return { active: false };
  }
  return {
    active: true,
    call_id: call.callId,
    callkit_uuid: call.callKitUuid,
    chat_id: call.chatId,
    state: call.state,
    role: call.hostId === uid ? 'host' : 'participant',
    media_type: call.mediaType,
    transport: 'livekit',
    participant_state: me.state,
    created_at: new Date(call.createdAt).toISOString(),
    updated_at: new Date(call.updatedAt).toISOString(),
    expires_at: new Date(call.expiresAt).toISOString(),
    revision: call.revision,
  };
}

export class MemoryCallRegistry {
  constructor(config, { now = () => Date.now() } = {}) {
    this.config = config;
    this._now = now;
    this._calls = new Map();
    this._userBusy = new Map();
    this._connections = new Map();
    this._tombstones = new Map();
    this._liveKitGroupCalls = new Map();
    this._liveKitRoomCalls = new Map();
    this._chatBusy = new Map();
    this._liveKitWebhookEvents = new Map();
    this._ready = false;
  }

  async start() {
    this._ready = true;
  }

  async stop() {
    this._ready = false;
    this._calls.clear();
    this._userBusy.clear();
    this._connections.clear();
    this._tombstones.clear();
    this._liveKitGroupCalls.clear();
    this._liveKitRoomCalls.clear();
    this._chatBusy.clear();
    this._liveKitWebhookEvents.clear();
  }

  isReady() {
    return this._ready;
  }

  _requireReady() {
    if (!this._ready) throw new Error('realtime_registry_unavailable');
  }

  _callExpiry(call) {
    return call.state === 'ringing'
      ? call.createdAt + this.config.ringingTtlMs
      : call.updatedAt + this.config.acceptedTtlMs;
  }

  _isExpired(call) {
    return Boolean(call && Number(call.expiresAt) <= this._now());
  }

  _busyMatches(userId, kind, ownerId) {
    const busy = this._userBusy.get(userId);
    return busy && busy.kind === kind && busy.ownerId === ownerId;
  }

  _connectionAlive(userId, connId) {
    if (!connId) return false;
    const lease = this._connections.get(connId);
    return Boolean(
      lease && lease.userId === userId && lease.expiresAt > this._now()
    );
  }

  _touchCall(call) {
    call.updatedAt = this._now();
    call.revision += 1;
    call.expiresAt = this._callExpiry(call);
    for (const uid of [call.callerId, call.calleeId]) {
      const busy = this._userBusy.get(uid);
      if (busy?.kind === 'dm' && busy.ownerId === call.callId) {
        busy.expiresAt = Math.max(
          call.expiresAt,
          this._now() + this.config.busyLeaseMs
        );
      }
    }
  }

  _deleteCall(call, reason = 'ended') {
    this._calls.delete(call.callId);
    for (const uid of [call.callerId, call.calleeId]) {
      if (this._busyMatches(uid, 'dm', call.callId)) {
        this._userBusy.delete(uid);
      }
    }
    const ended = {
      ...clone(call),
      state: 'ended',
      reason,
      endedAt: this._now(),
      revision: call.revision + 1,
    };
    this._tombstones.set(call.callId, {
      call: ended,
      expiresAt: this._now() + this.config.tombstoneTtlMs,
    });
    return ended;
  }

  async createDmCall({
    callId,
    callKitUuid,
    chatId,
    callerId,
    calleeId,
    mediaType,
    callerConnId,
  }) {
    this._requireReady();
    const id = normalizeId(callId);
    const caller = normalizeId(callerId);
    const callee = normalizeId(calleeId);
    if (!id || !caller || !callee) return { ok: false, code: 'invalid_call' };
    const tombstone = this._tombstones.get(id);
    if (tombstone?.expiresAt <= this._now()) {
      this._tombstones.delete(id);
    }
    if (this._calls.has(id) || this._tombstones.has(id)) {
      return { ok: false, code: 'call_id_exists' };
    }
    if (this._userBusy.has(caller)) {
      return { ok: false, code: 'busy', busyUserId: caller };
    }
    if (this._userBusy.has(callee)) {
      return { ok: false, code: 'busy', busyUserId: callee };
    }
    if (!callerConnId || !this._connectionAlive(caller, callerConnId)) {
      return { ok: false, code: 'connection_not_registered' };
    }

    const now = this._now();
    const call = {
      callId: id,
      callKitUuid:
        normalizeId(callKitUuid) || crypto.randomUUID().toLowerCase(),
      chatId: String(chatId),
      callerId: caller,
      calleeId: callee,
      state: 'ringing',
      mediaType: mediaType === 'video' ? 'video' : 'audio',
      createdAt: now,
      updatedAt: now,
      expiresAt: now + this.config.ringingTtlMs,
      revision: 1,
      media: {},
      disconnectDeadline: {},
    };
    call.media[caller] = { connId: callerConnId, fence: 1 };
    this._calls.set(id, call);
    const busyExpiry = Math.max(
      call.expiresAt,
      now + this.config.busyLeaseMs
    );
    this._userBusy.set(caller, {
      kind: 'dm',
      ownerId: id,
      instanceId: null,
      expiresAt: busyExpiry,
    });
    this._userBusy.set(callee, {
      kind: 'dm',
      ownerId: id,
      instanceId: null,
      expiresAt: busyExpiry,
    });
    return { ok: true, call: clone(call) };
  }

  async getCall(callId) {
    this._requireReady();
    return clone(this._calls.get(normalizeId(callId)) || null);
  }

  async getUserDmCallId(userId) {
    this._requireReady();
    const busy = this._userBusy.get(normalizeId(userId));
    return busy?.kind === 'dm' ? busy.ownerId : null;
  }

  async getStatus(userId, { callId } = {}) {
    this._requireReady();
    const uid = normalizeId(userId);
    if (!uid) return { active: false };
    const requested = normalizeId(callId);
    const busy = this._userBusy.get(uid);
    if (busy?.kind === 'livekit_group') {
      const groupCall = this._liveKitGroupCalls.get(busy.ownerId);
      if (
        groupCall &&
        !this._isExpired(groupCall) &&
        (!requested || requested === groupCall.callId)
      ) {
        return publicLiveKitGroupStatus(groupCall, uid);
      }
      if (requested) return { active: false };
    }
    const activeId = await this.getUserDmCallId(uid);
    if (!activeId || (requested && requested !== activeId)) {
      return { active: false };
    }
    const call = this._calls.get(activeId);
    if (this._isExpired(call)) return { active: false };
    return publicCallStatus(call, uid);
  }

  _touchLiveKitGroupCall(call) {
    const now = this._now();
    call.updatedAt = now;
    call.expiresAt = now + this.config.liveKitGroupCallTtlMs;
    call.revision += 1;
    const chatBusy = this._chatBusy.get(call.chatId);
    if (
      chatBusy?.kind === 'livekit_group' &&
      chatBusy.ownerId === call.callId
    ) {
      chatBusy.expiresAt = call.expiresAt;
    }
    for (const uid of call.participantOrder) {
      const busy = this._userBusy.get(uid);
      if (
        busy?.kind === 'livekit_group' &&
        busy.ownerId === call.callId
      ) {
        busy.expiresAt = Math.max(
          call.expiresAt,
          now + this.config.busyLeaseMs
        );
      }
    }
  }

  _releaseLiveKitParticipantBusy(call, userId) {
    const uid = normalizeId(userId);
    if (this._busyMatches(uid, 'livekit_group', call.callId)) {
      this._userBusy.delete(uid);
    }
  }

  _endLiveKitGroupCall(call, reason = 'ended') {
    this._liveKitGroupCalls.delete(call.callId);
    if (this._liveKitRoomCalls.get(call.roomName) === call.callId) {
      this._liveKitRoomCalls.delete(call.roomName);
    }
    const chatBusy = this._chatBusy.get(call.chatId);
    if (
      chatBusy?.kind === 'livekit_group' &&
      chatBusy.ownerId === call.callId
    ) {
      this._chatBusy.delete(call.chatId);
    }
    for (const uid of call.participantOrder) {
      this._releaseLiveKitParticipantBusy(call, uid);
    }
    const now = this._now();
    const ended = {
      ...clone(call),
      kind: 'livekit_group',
      state: 'ended',
      reason,
      endedAt: now,
      updatedAt: now,
      revision: call.revision + 1,
    };
    this._tombstones.set(call.callId, {
      call: ended,
      expiresAt: now + this.config.tombstoneTtlMs,
    });
    return ended;
  }

  async createLiveKitGroupCall({
    callId,
    callKitUuid,
    roomName,
    chatId,
    hostId,
    mediaType,
    participants,
    instanceId,
  }) {
    this._requireReady();
    const id = normalizeId(callId);
    const room = normalizeId(roomName);
    const chat = normalizeId(chatId);
    const host = normalizeId(hostId);
    if (!id || !room || !chat || !host || !Array.isArray(participants)) {
      return { ok: false, code: 'invalid_call' };
    }
    const existingTombstone = this._tombstones.get(id);
    if (existingTombstone?.expiresAt <= this._now()) {
      this._tombstones.delete(id);
    }
    if (
      this._calls.has(id) ||
      this._liveKitGroupCalls.has(id) ||
      this._tombstones.has(id)
    ) {
      return { ok: false, code: 'call_id_exists' };
    }
    let chatBusy = this._chatBusy.get(chat);
    if (chatBusy?.expiresAt <= this._now()) {
      this._chatBusy.delete(chat);
      chatBusy = null;
    }
    if (chatBusy) {
      return {
        ok: false,
        code: 'chat_call_active',
        activeCallId: chatBusy.ownerId,
      };
    }
    if (this._userBusy.has(host)) {
      return { ok: false, code: 'busy', busyUserId: host };
    }

    const unique = new Map();
    for (const raw of participants) {
      const uid = normalizeId(raw?.userId);
      if (!uid || unique.has(uid)) continue;
      unique.set(uid, {
        userId: uid,
        label: String(raw?.label || '').slice(0, 80),
      });
    }
    if (!unique.has(host)) {
      unique.set(host, { userId: host, label: '' });
    }

    const admitted = [];
    for (const entry of unique.values()) {
      if (entry.userId !== host && this._userBusy.has(entry.userId)) continue;
      admitted.push(entry);
    }
    const now = this._now();
    const participantMap = {};
    for (const entry of admitted) {
      participantMap[entry.userId] = {
        ...entry,
        state: entry.userId === host ? 'joined' : 'invited',
        invitedAt: now,
        ...(entry.userId === host ? { joinedAt: now } : {}),
      };
    }
    const call = {
      kind: 'livekit_group',
      callId: id,
      callKitUuid:
        normalizeId(callKitUuid) || crypto.randomUUID().toLowerCase(),
      roomName: room,
      chatId: chat,
      hostId: host,
      mediaType: mediaType === 'video' ? 'video' : 'audio',
      state: 'ringing',
      createdAt: now,
      updatedAt: now,
      ringingExpiresAt: now + this.config.ringingTtlMs,
      expiresAt: now + this.config.liveKitGroupCallTtlMs,
      revision: 1,
      hadGuestJoin: false,
      participantOrder: admitted.map((entry) => entry.userId),
      participants: participantMap,
    };
    this._liveKitGroupCalls.set(id, call);
    this._liveKitRoomCalls.set(room, id);
    this._chatBusy.set(chat, {
      kind: 'livekit_group',
      ownerId: id,
      instanceId: normalizeId(instanceId),
      expiresAt: call.expiresAt,
    });
    for (const uid of call.participantOrder) {
      this._userBusy.set(uid, {
        kind: 'livekit_group',
        ownerId: id,
        instanceId: normalizeId(instanceId),
        expiresAt: Math.max(
          call.expiresAt,
          now + this.config.busyLeaseMs
        ),
      });
    }
    return { ok: true, call: clone(call) };
  }

  async getLiveKitGroupCall(callId) {
    this._requireReady();
    const call = this._liveKitGroupCalls.get(normalizeId(callId));
    return this._isExpired(call) ? null : clone(call || null);
  }

  async getLiveKitGroupCallRecord(callId) {
    this._requireReady();
    return clone(
      this._liveKitGroupCalls.get(normalizeId(callId)) || null
    );
  }

  async getLiveKitGroupCallTombstone(callId) {
    this._requireReady();
    const tombstone = this._tombstones.get(normalizeId(callId));
    if (
      !tombstone ||
      tombstone.expiresAt <= this._now() ||
      tombstone.call?.kind !== 'livekit_group'
    ) {
      return null;
    }
    return clone(tombstone.call);
  }

  async getLiveKitGroupCallByRoom(roomName) {
    this._requireReady();
    const callId = this._liveKitRoomCalls.get(normalizeId(roomName));
    return callId ? this.getLiveKitGroupCall(callId) : null;
  }

  async getLiveKitGroupCallForChat(chatId) {
    this._requireReady();
    const busy = this._chatBusy.get(normalizeId(chatId));
    if (busy?.kind !== 'livekit_group') return null;
    return this.getLiveKitGroupCall(busy.ownerId);
  }

  async getUserLiveKitGroupCallId(userId) {
    this._requireReady();
    const busy = await this.getBusy(userId);
    return busy?.kind === 'livekit_group' ? busy.ownerId : null;
  }

  async joinLiveKitGroupCall({
    callId,
    userId,
    connId,
    answerTokenHash,
  }) {
    this._requireReady();
    const call = this._liveKitGroupCalls.get(normalizeId(callId));
    if (!call) return { ok: false, code: 'call_not_found' };
    if (this._isExpired(call)) return { ok: false, code: 'call_expired' };
    const uid = normalizeId(userId);
    const connectionId = normalizeId(connId);
    const me = groupParticipant(call, uid);
    if (!me) return { ok: false, code: 'forbidden' };
    if (connectionId && !this._connectionAlive(uid, connectionId)) {
      return { ok: false, code: 'connection_not_registered' };
    }
    if (['declined', 'left', 'timed_out'].includes(me.state)) {
      return { ok: false, code: 'invite_inactive' };
    }
    const alreadyJoined = me.state === 'joined';
    if (
      alreadyJoined &&
      connectionId &&
      me.answerConnId &&
      me.answerConnId !== connectionId &&
      this._connectionAlive(uid, me.answerConnId)
    ) {
      return { ok: false, code: 'media_owned_elsewhere' };
    }
    me.state = 'joined';
    me.joinedAt ??= this._now();
    if (connectionId) me.answerConnId = connectionId;
    if (answerTokenHash) me.answerTokenHash = String(answerTokenHash);
    delete me.disconnectDeadline;
    if (uid !== call.hostId) call.hadGuestJoin = true;
    call.state = 'active';
    this._touchLiveKitGroupCall(call);
    return { ok: true, alreadyJoined, call: clone(call) };
  }

  async rejectLiveKitGroupCall({
    callId,
    userId,
    reason = 'declined',
  }) {
    this._requireReady();
    const call = this._liveKitGroupCalls.get(normalizeId(callId));
    if (!call) return { ok: false, code: 'call_not_found' };
    const uid = normalizeId(userId);
    const me = groupParticipant(call, uid);
    if (!me) return { ok: false, code: 'forbidden' };
    if (uid === call.hostId) {
      return { ok: false, code: 'host_cannot_reject' };
    }
    if (!['declined', 'left', 'timed_out'].includes(me.state)) {
      me.state = 'declined';
      me.reason = String(reason).slice(0, 64);
      me.leftAt = this._now();
      this._releaseLiveKitParticipantBusy(call, uid);
      this._touchLiveKitGroupCall(call);
    }
    return { ok: true, call: clone(call) };
  }

  async leaveLiveKitGroupCall({
    callId,
    userId,
    reason = 'left',
    webhook = false,
  }) {
    this._requireReady();
    const call = this._liveKitGroupCalls.get(normalizeId(callId));
    if (!call) return { ok: false, code: 'call_not_found' };
    const uid = normalizeId(userId);
    const me = groupParticipant(call, uid);
    if (!me) return { ok: false, code: 'forbidden' };
    if (['left', 'declined', 'timed_out'].includes(me.state)) {
      return { ok: true, call: clone(call), alreadyLeft: true };
    }

    if (webhook) {
      me.state = 'disconnected';
      me.disconnectDeadline = this._now() + this.config.disconnectGraceMs;
      this._touchLiveKitGroupCall(call);
      return {
        ok: true,
        call: clone(call),
        reconnectGrace: true,
        hostGrace: uid === call.hostId,
      };
    }

    me.state = 'left';
    me.reason = String(reason).slice(0, 64);
    me.leftAt = this._now();
    this._releaseLiveKitParticipantBusy(call, uid);
    if (uid === call.hostId) {
      return {
        ok: true,
        ended: true,
        call: this._endLiveKitGroupCall(call, 'host_left'),
      };
    }
    const joinedCount = Object.values(call.participants).filter(
      (entry) => entry.state === 'joined'
    ).length;
    if (call.hadGuestJoin && joinedCount <= 1) {
      return {
        ok: true,
        ended: true,
        call: this._endLiveKitGroupCall(call, 'empty'),
      };
    }
    this._touchLiveKitGroupCall(call);
    return { ok: true, call: clone(call) };
  }

  async finishLiveKitGroupCall({ callId, reason = 'ended' }) {
    this._requireReady();
    const call = this._liveKitGroupCalls.get(normalizeId(callId));
    if (!call) {
      const tombstone = this._tombstones.get(normalizeId(callId));
      return tombstone
        ? { ok: true, alreadyEnded: true, call: clone(tombstone.call) }
        : { ok: false, code: 'call_not_found' };
    }
    return {
      ok: true,
      ended: true,
      call: this._endLiveKitGroupCall(call, reason),
    };
  }

  async claimLiveKitWebhookEvent(eventId, ttlMs = this.config.tombstoneTtlMs) {
    this._requireReady();
    const id = normalizeId(eventId);
    if (!id) return false;
    const current = this._liveKitWebhookEvents.get(id);
    if (current && current > this._now()) return false;
    this._liveKitWebhookEvents.set(id, this._now() + ttlMs);
    return true;
  }

  async acquireChatBusy({ chatId, kind, ownerId, instanceId }) {
    this._requireReady();
    const chat = normalizeId(chatId);
    const owner = normalizeId(ownerId);
    if (!chat || !owner || !kind) {
      return { ok: false, code: 'invalid_chat_busy' };
    }
    let current = this._chatBusy.get(chat);
    if (current?.expiresAt <= this._now()) {
      this._chatBusy.delete(chat);
      current = null;
    }
    if (current) {
      if (current.kind === kind && current.ownerId === owner) {
        current.expiresAt = this._now() + this.config.busyLeaseMs;
        return { ok: true, acquired: false };
      }
      return { ok: false, code: 'chat_call_active', busy: clone(current) };
    }
    this._chatBusy.set(chat, {
      kind: String(kind),
      ownerId: owner,
      instanceId: normalizeId(instanceId),
      expiresAt: this._now() + this.config.busyLeaseMs,
    });
    return { ok: true, acquired: true };
  }

  async releaseChatBusy({ chatId, kind, ownerId }) {
    this._requireReady();
    const chat = normalizeId(chatId);
    const current = this._chatBusy.get(chat);
    if (
      current?.kind === String(kind) &&
      current.ownerId === normalizeId(ownerId)
    ) {
      this._chatBusy.delete(chat);
      return true;
    }
    return false;
  }

  async getChatBusy(chatId) {
    this._requireReady();
    const chat = normalizeId(chatId);
    const current = this._chatBusy.get(chat);
    if (current?.expiresAt <= this._now()) {
      this._chatBusy.delete(chat);
      return null;
    }
    return clone(current || null);
  }

  _bindMedia(call, userId, connId) {
    const uid = normalizeId(userId);
    const cid = normalizeId(connId);
    if (!uid || !cid || !this._connectionAlive(uid, cid)) {
      return { ok: false, code: 'connection_not_registered' };
    }
    const current = mediaBinding(call, uid);
    if (current?.connId === cid) {
      delete call.disconnectDeadline[uid];
      return { ok: true, fence: current.fence, changed: false };
    }
    if (current && this._connectionAlive(uid, current.connId)) {
      return { ok: false, code: 'media_owned_elsewhere' };
    }
    const fence = (current?.fence || 0) + 1;
    call.media[uid] = { connId: cid, fence };
    delete call.disconnectDeadline[uid];
    return { ok: true, fence, changed: true };
  }

  async acceptDmCall({ callId, userId, connId }) {
    this._requireReady();
    const call = await this.getCall(callId);
    if (!call) return { ok: false, code: 'call_not_found' };
    if (this._isExpired(call)) return { ok: false, code: 'call_expired' };
    const uid = normalizeId(userId);
    if (!participant(call, uid)) return { ok: false, code: 'forbidden' };
    if (call.calleeId !== uid) {
      return { ok: false, code: 'only_callee_can_accept' };
    }
    if (call.state !== 'ringing') {
      const stored = this._calls.get(call.callId);
      const binding = this._bindMedia(stored, uid, connId);
      if (!binding.ok) return binding;
      if (binding.changed) this._touchCall(stored);
      return {
        ok: true,
        call: clone(stored),
        alreadyAccepted: true,
        resumed: binding.changed,
        fence: binding.fence,
      };
    }
    const stored = this._calls.get(call.callId);
    const binding = this._bindMedia(stored, uid, connId);
    if (!binding.ok) return binding;
    stored.state = 'accepted';
    stored.disconnectDeadline = {};
    this._touchCall(stored);
    return { ok: true, call: clone(stored), fence: binding.fence };
  }

  async resumeDmCall({ callId, userId, connId }) {
    this._requireReady();
    const call = await this.getCall(callId);
    if (!call || !participant(call, userId)) {
      return { ok: false, code: 'call_not_found', status: { active: false } };
    }
    if (this._isExpired(call)) {
      return { ok: false, code: 'call_expired', status: { active: false } };
    }
    const stored = this._calls.get(call.callId);
    if (stored.state === 'accepted') {
      const binding = this._bindMedia(stored, userId, connId);
      if (!binding.ok) {
        return {
          ok: false,
          code: binding.code,
          status: publicCallStatus(stored, userId),
        };
      }
      this._touchCall(stored);
      return {
        ok: true,
        call: clone(stored),
        resumed: binding.changed,
        fence: binding.fence,
        status: publicCallStatus(stored, userId),
      };
    }
    return {
      ok: true,
      call: clone(stored),
      resumed: false,
      status: publicCallStatus(stored, userId),
    };
  }

  async authorizeMedia({
    callId,
    userId,
    connId,
    mediaType,
  }) {
    this._requireReady();
    const call = await this.getCall(callId);
    if (!call) return { ok: false, code: 'call_not_found' };
    if (this._isExpired(call)) return { ok: false, code: 'call_expired' };
    if (!participant(call, userId)) return { ok: false, code: 'forbidden' };
    if (call.state !== 'accepted') {
      return { ok: false, code: 'call_not_accepted' };
    }
    const stored = this._calls.get(call.callId);
    const binding = this._bindMedia(stored, userId, connId);
    if (!binding.ok) return binding;
    if (mediaType === 'audio' || mediaType === 'video') {
      stored.mediaType = mediaType;
    }
    this._touchCall(stored);
    return { ok: true, call: clone(stored), fence: binding.fence };
  }

  async terminateDmCall({
    callId,
    userId,
    connId,
    reason = 'ended',
    ringingOnly = false,
  }) {
    this._requireReady();
    const call = await this.getCall(callId);
    if (!call) return { ok: false, code: 'call_not_found' };
    if (this._isExpired(call)) return { ok: false, code: 'call_expired' };
    const uid = normalizeId(userId);
    if (!participant(call, uid)) return { ok: false, code: 'forbidden' };
    if (ringingOnly && call.state !== 'ringing') {
      return { ok: false, code: 'call_already_accepted' };
    }
    if (call.state === 'accepted') {
      const binding = mediaBinding(call, uid);
      if (
        binding &&
        binding.connId !== normalizeId(connId) &&
        this._connectionAlive(uid, binding.connId)
      ) {
        return { ok: false, code: 'media_owned_elsewhere' };
      }
    }
    return {
      ok: true,
      call: this._deleteCall(this._calls.get(call.callId), reason),
    };
  }

  async registerConnection({ userId, connId, instanceId }) {
    this._requireReady();
    const uid = normalizeId(userId);
    const cid = normalizeId(connId);
    if (!uid || !cid) return false;
    this._connections.set(cid, {
      userId: uid,
      instanceId: normalizeId(instanceId),
      expiresAt: this._now() + this.config.connectionLeaseMs,
    });
    return true;
  }

  async heartbeatConnection({ userId, connId, instanceId }) {
    this._requireReady();
    const uid = normalizeId(userId);
    const cid = normalizeId(connId);
    const lease = this._connections.get(cid);
    if (!lease || lease.userId !== uid) return false;
    lease.instanceId = normalizeId(instanceId);
    lease.expiresAt = this._now() + this.config.connectionLeaseMs;
    const busy = this._userBusy.get(uid);
    if (busy) {
      busy.expiresAt = Math.max(
        busy.expiresAt,
        this._now() + this.config.busyLeaseMs
      );
      if (busy.kind === 'dm') {
        const call = this._calls.get(busy.ownerId);
        if (
          call?.state === 'accepted' &&
          mediaBinding(call, uid)?.connId === cid
        ) {
          call.expiresAt = this._now() + this.config.acceptedTtlMs;
        }
      } else if (busy.kind === 'livekit_group') {
        const call = this._liveKitGroupCalls.get(busy.ownerId);
        const me = groupParticipant(call, uid);
        if (call && me && ['joined', 'disconnected'].includes(me.state)) {
          this._touchLiveKitGroupCall(call);
        }
      }
    }
    return true;
  }

  async unregisterConnection({ userId, connId }) {
    this._requireReady();
    const uid = normalizeId(userId);
    const cid = normalizeId(connId);
    const lease = this._connections.get(cid);
    if (lease?.userId === uid) this._connections.delete(cid);
    const dmId = await this.getUserDmCallId(uid);
    const call = dmId ? this._calls.get(dmId) : null;
    if (
      call &&
      !this._isExpired(call) &&
      mediaBinding(call, uid)?.connId === cid
    ) {
      call.disconnectDeadline[uid] =
        this._now() +
        (call.state === 'accepted'
          ? this.config.disconnectGraceMs
          : this.config.ringingDisconnectGraceMs);
      this._touchCall(call);
      return { wasMedia: true, call: clone(call) };
    }
    return { wasMedia: false, call: clone(call) };
  }

  async acquireBusy({ userId, kind, ownerId, instanceId }) {
    this._requireReady();
    const uid = normalizeId(userId);
    const owner = normalizeId(ownerId);
    if (!uid || !owner || !kind) return { ok: false, code: 'invalid_busy' };
    let current = this._userBusy.get(uid);
    if (current?.kind !== 'dm' && current?.expiresAt <= this._now()) {
      this._userBusy.delete(uid);
      current = null;
    }
    if (current) {
      if (current.kind === kind && current.ownerId === owner) {
        current.expiresAt = this._now() + this.config.busyLeaseMs;
        return { ok: true, acquired: false };
      }
      return { ok: false, code: 'busy', busy: clone(current) };
    }
    this._userBusy.set(uid, {
      kind: String(kind),
      ownerId: owner,
      instanceId: normalizeId(instanceId),
      expiresAt: this._now() + this.config.busyLeaseMs,
    });
    return { ok: true, acquired: true };
  }

  async releaseBusy({ userId, kind, ownerId }) {
    this._requireReady();
    const uid = normalizeId(userId);
    if (this._busyMatches(uid, String(kind), normalizeId(ownerId))) {
      this._userBusy.delete(uid);
      return true;
    }
    return false;
  }

  async getBusy(userId) {
    this._requireReady();
    const uid = normalizeId(userId);
    const busy = this._userBusy.get(uid);
    if (busy?.kind !== 'dm' && busy?.expiresAt <= this._now()) {
      this._userBusy.delete(uid);
      return null;
    }
    return clone(busy || null);
  }

  async sweepExpired() {
    this._requireReady();
    const now = this._now();
    for (const [connId, lease] of this._connections) {
      if (lease.expiresAt <= now) this._connections.delete(connId);
    }
    for (const [callId, tombstone] of this._tombstones) {
      if (tombstone.expiresAt <= now) this._tombstones.delete(callId);
    }
    for (const [chatId, busy] of this._chatBusy) {
      if (busy.expiresAt <= now) this._chatBusy.delete(chatId);
    }
    for (const [eventId, expiresAt] of this._liveKitWebhookEvents) {
      if (expiresAt <= now) this._liveKitWebhookEvents.delete(eventId);
    }
    for (const [uid, busy] of this._userBusy) {
      if (busy.expiresAt <= now && busy.kind !== 'dm') {
        this._userBusy.delete(uid);
      }
    }

    const ended = [];
    for (const call of [...this._calls.values()]) {
      for (const uid of [call.callerId, call.calleeId]) {
        const binding = mediaBinding(call, uid);
        if (
          binding &&
          !this._connectionAlive(uid, binding.connId) &&
          !call.disconnectDeadline[uid]
        ) {
          call.disconnectDeadline[uid] =
            now +
            (call.state === 'accepted'
              ? this.config.disconnectGraceMs
              : this.config.ringingDisconnectGraceMs);
        }
      }
      const disconnected = Object.values(call.disconnectDeadline).some(
        (deadline) => Number(deadline) <= now
      );
      if (disconnected) {
        ended.push(this._deleteCall(call, 'disconnected'));
      } else if (call.state === 'ringing' && call.expiresAt <= now) {
        ended.push(this._deleteCall(call, 'ringing_timeout'));
      } else if (call.state === 'accepted' && call.expiresAt <= now) {
        ended.push(this._deleteCall(call, 'call_ttl'));
      }
    }
    for (const call of [...this._liveKitGroupCalls.values()]) {
      let disconnectedGuestExpired = false;
      for (const uid of call.participantOrder) {
        const participant = groupParticipant(call, uid);
        if (
          participant?.state !== 'disconnected' ||
          Number(participant.disconnectDeadline) > now
        ) {
          continue;
        }
        if (uid === call.hostId) {
          ended.push(
            this._endLiveKitGroupCall(call, 'host_disconnected')
          );
          disconnectedGuestExpired = false;
          break;
        }
        participant.state = 'left';
        participant.leftAt = now;
        delete participant.disconnectDeadline;
        this._releaseLiveKitParticipantBusy(call, uid);
        disconnectedGuestExpired = true;
      }
      if (!this._liveKitGroupCalls.has(call.callId)) continue;
      if (disconnectedGuestExpired) {
        const joinedCount = Object.values(call.participants).filter(
          (entry) => entry.state === 'joined'
        ).length;
        if (call.hadGuestJoin && joinedCount <= 1) {
          ended.push(this._endLiveKitGroupCall(call, 'empty'));
          continue;
        }
        this._touchLiveKitGroupCall(call);
      }
      if (!call.hadGuestJoin && Number(call.ringingExpiresAt) <= now) {
        ended.push(this._endLiveKitGroupCall(call, 'no_answer'));
        continue;
      }
      if (Number(call.expiresAt) <= now) {
        ended.push(this._endLiveKitGroupCall(call, 'call_ttl'));
        continue;
      }
      if (Number(call.ringingExpiresAt) <= now) {
        let changed = false;
        for (const uid of call.participantOrder) {
          const entry = groupParticipant(call, uid);
          if (entry?.state !== 'invited') continue;
          entry.state = 'timed_out';
          entry.leftAt = now;
          this._releaseLiveKitParticipantBusy(call, uid);
          changed = true;
        }
        if (changed) this._touchLiveKitGroupCall(call);
      }
    }
    return ended;
  }
}
