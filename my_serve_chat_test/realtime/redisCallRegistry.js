import crypto from 'node:crypto';

import {
  publicCallStatus,
  publicLiveKitGroupStatus,
} from './memoryCallRegistry.js';
import { RealtimeUnavailableError } from './errors.js';
import {
  ACQUIRE_BUSY_LUA,
  CREATE_DM_CALL_LUA,
  CREATE_LIVEKIT_GROUP_CALL_LUA,
  HEARTBEAT_CONNECTION_LUA,
  MUTATE_DM_CALL_LUA,
  REGISTER_CONNECTION_LUA,
  RELEASE_BUSY_LUA,
  SWEEP_DM_CALL_LUA,
  UNREGISTER_CONNECTION_LUA,
} from './redisScripts.js';

function normalizeId(value) {
  const id = value?.toString().trim();
  return id || null;
}

function parseJson(raw, fallback = null) {
  if (typeof raw !== 'string' || raw.length === 0) return fallback;
  try {
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

export class RedisCallRegistry {
  constructor(config, client) {
    this.config = config;
    this.client = client;
    this.prefix = `rt:{${config.namespace}}:v1:`;
    this.deadlinesKey = `${this.prefix}call-deadlines`;
    this.groupDeadlinesKey = `${this.prefix}livekit-group-deadlines`;
  }

  async start() {}

  async stop() {}

  isReady() {
    return Boolean(this.client?.isReady);
  }

  _requireReady() {
    if (!this.isReady()) throw new RealtimeUnavailableError();
  }

  async _runCommand(command) {
    let timer;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => {
        const error = new Error('redis_command_timeout');
        error.code = 'redis_command_timeout';
        reject(error);
      }, this.config.redisCommandTimeoutMs);
      timer.unref?.();
    });
    try {
      return await Promise.race([command, timeout]);
    } catch (error) {
      if (error?.code === 'redis_command_timeout') {
        try {
          this.client.destroy();
        } catch {}
      }
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }

  _hash(value) {
    return crypto
      .createHash('sha256')
      .update(String(value))
      .digest('base64url');
  }

  _callHash(callId) {
    return this._hash(`call:${callId}`);
  }

  _userHash(userId) {
    return this._hash(`user:${userId}`);
  }

  _connHash(connId) {
    return this._hash(`conn:${connId}`);
  }

  _callKeyFromHash(hash) {
    return `${this.prefix}call:${hash}`;
  }

  _callKey(callId) {
    return this._callKeyFromHash(this._callHash(callId));
  }

  _groupHash(callId) {
    return this._hash(`livekit-group:${callId}`);
  }

  _groupKeyFromHash(hash) {
    return `${this.prefix}livekit-group:${hash}`;
  }

  _groupKey(callId) {
    return this._groupKeyFromHash(this._groupHash(callId));
  }

  _groupRoomKey(roomName) {
    return `${this.prefix}livekit-room:${this._hash(`room:${roomName}`)}`;
  }

  _chatBusyKey(chatId) {
    return `${this.prefix}chat-busy:${this._hash(`chat:${chatId}`)}`;
  }

  _groupLockKey(callId) {
    return `${this.prefix}livekit-lock:${this._groupHash(callId)}`;
  }

  _webhookEventKey(eventId) {
    return `${this.prefix}livekit-webhook:${this._hash(`event:${eventId}`)}`;
  }

  _tombstoneKey(callId) {
    return `${this.prefix}tomb:${this._callHash(callId)}`;
  }

  _busyKey(userId) {
    return `${this.prefix}busy:${this._userHash(userId)}`;
  }

  _connectionKeyFromHash(hash) {
    return `${this.prefix}conn:${hash}`;
  }

  _connectionKey(connId) {
    return this._connectionKeyFromHash(this._connHash(connId));
  }

  _dummyConnectionKey(seed) {
    return this._connectionKeyFromHash(this._hash(`missing:${seed}`));
  }

  _callKeyTtlMs() {
    return (
      this.config.acceptedTtlMs +
      this.config.disconnectGraceMs +
      this.config.tombstoneTtlMs
    );
  }

  _groupKeyTtlMs() {
    return (
      this.config.liveKitGroupCallTtlMs +
      this.config.disconnectGraceMs +
      this.config.tombstoneTtlMs
    );
  }

  _busyTtlMs() {
    return this.config.busyLeaseMs;
  }

  _groupBusyTtlMs() {
    return Math.max(
      this.config.busyLeaseMs,
      this.config.liveKitGroupCallTtlMs + this.config.disconnectGraceMs
    );
  }

  async _eval(script, keys, args) {
    this._requireReady();
    try {
      return await this._runCommand(
        this.client.eval(script, {
          keys,
          arguments: args.map((value) => String(value ?? '')),
        })
      );
    } catch (error) {
      throw new RealtimeUnavailableError('realtime_redis_command_failed', {
        cause: error,
      });
    }
  }

  async _get(key) {
    this._requireReady();
    try {
      return await this._runCommand(this.client.get(key));
    } catch (error) {
      throw new RealtimeUnavailableError('realtime_redis_command_failed', {
        cause: error,
      });
    }
  }

  async _withLiveKitGroupLock(callId, operation) {
    this._requireReady();
    const key = this._groupLockKey(callId);
    const token = crypto.randomUUID();
    let acquired = false;
    for (let attempt = 0; attempt < 80; attempt += 1) {
      const result = await this._runCommand(
        this.client.set(key, token, { NX: true, PX: 5_000 })
      );
      if (result === 'OK') {
        acquired = true;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    if (!acquired) {
      return { ok: false, code: 'call_busy' };
    }
    try {
      return await operation();
    } finally {
      try {
        await this._runCommand(
          this.client.eval(
            `if redis.call('GET', KEYS[1]) == ARGV[1] then
               return redis.call('DEL', KEYS[1])
             end
             return 0`,
            { keys: [key], arguments: [token] }
          )
        );
      } catch {}
    }
  }

  async _persistLiveKitGroupCall(call) {
    const ttl = this._groupKeyTtlMs();
    const groupHash = this._groupHash(call.callId);
    const dueCandidates = [
      Number(call.expiresAt),
      ...Object.values(call.participants || {})
        .map((entry) => Number(entry.disconnectDeadline))
        .filter(Number.isFinite),
    ];
    if (!call.hadGuestJoin) {
      dueCandidates.push(Number(call.ringingExpiresAt));
    }
    const multi = this.client
      .multi()
      .set(this._groupKeyFromHash(groupHash), JSON.stringify(call), {
        PX: ttl,
      })
      .set(this._groupRoomKey(call.roomName), String(call.callId), { PX: ttl })
      .zAdd(this.groupDeadlinesKey, {
        score: Math.min(...dueCandidates.filter(Number.isFinite)),
        value: groupHash,
      });
    await this._runCommand(multi.exec());

    await this._eval(
      ACQUIRE_BUSY_LUA,
      [this._chatBusyKey(call.chatId)],
      [
        'livekit_group',
        call.callId,
        JSON.stringify({
          kind: 'livekit_group',
          ownerId: call.callId,
          groupHash,
        }),
        this._groupBusyTtlMs(),
      ]
    );
    for (const uid of call.participantOrder || []) {
      const participant = call.participants?.[uid];
      if (
        !participant ||
        ['declined', 'left', 'timed_out'].includes(participant.state)
      ) {
        continue;
      }
      await this._eval(
        ACQUIRE_BUSY_LUA,
        [this._busyKey(uid)],
        [
          'livekit_group',
          call.callId,
          JSON.stringify({
            kind: 'livekit_group',
            ownerId: call.callId,
            groupHash,
          }),
          this._groupBusyTtlMs(),
        ]
      );
    }
  }

  async _releaseExact(key, kind, ownerId) {
    const raw = await this._eval(
      RELEASE_BUSY_LUA,
      [key],
      [String(kind), String(ownerId)]
    );
    return Number(raw) === 1;
  }

  async _endLiveKitGroupCallLocked(call, reason) {
    const now = await this._redisNow();
    const ended = {
      ...call,
      kind: 'livekit_group',
      state: 'ended',
      reason,
      endedAt: now,
      updatedAt: now,
      revision: (Number(call.revision) || 0) + 1,
    };
    const groupHash = this._groupHash(call.callId);
    const multi = this.client
      .multi()
      .del(this._groupKeyFromHash(groupHash))
      .del(this._groupRoomKey(call.roomName))
      .set(this._tombstoneKey(call.callId), JSON.stringify(ended), {
        PX: this.config.tombstoneTtlMs,
      })
      .zRem(this.groupDeadlinesKey, groupHash);
    await this._runCommand(multi.exec());
    await this._releaseExact(
      this._chatBusyKey(call.chatId),
      'livekit_group',
      call.callId
    );
    for (const uid of call.participantOrder || []) {
      await this._releaseExact(
        this._busyKey(uid),
        'livekit_group',
        call.callId
      );
    }
    return ended;
  }

  async _redisNow() {
    this._requireReady();
    try {
      const result = await this._runCommand(
        this.client.sendCommand(['TIME'])
      );
      const seconds = Number(result?.[0]);
      const micros = Number(result?.[1]);
      if (!Number.isFinite(seconds) || !Number.isFinite(micros)) {
        throw new Error('invalid_redis_time');
      }
      return seconds * 1000 + Math.floor(micros / 1000);
    } catch (error) {
      throw new RealtimeUnavailableError('realtime_redis_command_failed', {
        cause: error,
      });
    }
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
    const id = normalizeId(callId);
    const caller = normalizeId(callerId);
    const callee = normalizeId(calleeId);
    if (!id || !caller || !callee) return { ok: false, code: 'invalid_call' };
    const now = Date.now();
    const callHash = this._callHash(id);
    const connId = normalizeId(callerConnId) || '';
    const connHash = connId ? this._connHash(connId) : '';
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
    const callerBusy = {
      kind: 'dm',
      ownerId: id,
      callHash,
      instanceId: null,
    };
    const calleeBusy = { ...callerBusy };
    const raw = await this._eval(
      CREATE_DM_CALL_LUA,
      [
        this._callKeyFromHash(callHash),
        this._tombstoneKey(id),
        this._busyKey(caller),
        this._busyKey(callee),
        this.deadlinesKey,
        connId
          ? this._connectionKeyFromHash(connHash)
          : this._dummyConnectionKey(id),
      ],
      [
        JSON.stringify(call),
        JSON.stringify(callerBusy),
        JSON.stringify(calleeBusy),
        this._callKeyTtlMs(),
        this._busyTtlMs(),
        connId,
        connHash,
        this.config.connectionLeaseMs,
        callHash,
        `${this.prefix}call:`,
        this.config.ringingTtlMs,
      ]
    );
    const result = parseJson(raw, { ok: false, code: 'registry_error' });
    if (result.code === 'caller_busy') {
      return { ok: false, code: 'busy', busyUserId: caller };
    }
    if (result.code === 'callee_busy') {
      return { ok: false, code: 'busy', busyUserId: callee };
    }
    return result;
  }

  async _readCallByHash(callHash) {
    const raw = await this._get(this._callKeyFromHash(callHash));
    return parseJson(raw);
  }

  async getCall(callId) {
    const id = normalizeId(callId);
    if (!id) return null;
    const hash = this._callHash(id);
    return this._readCallByHash(hash);
  }

  async _getBusyRaw(userId) {
    return parseJson(await this._get(this._busyKey(userId)));
  }

  async getUserDmCallId(userId) {
    const uid = normalizeId(userId);
    if (!uid) return null;
    const busy = await this._getBusyRaw(uid);
    if (busy?.kind !== 'dm' || !busy.ownerId || !busy.callHash) return null;
    const call = await this._readCallByHash(busy.callHash);
    if (!call || String(call.callId) !== String(busy.ownerId)) {
      await this._eval(
        RELEASE_BUSY_LUA,
        [this._busyKey(uid)],
        ['dm', String(busy.ownerId)]
      );
      return null;
    }
    return String(busy.ownerId);
  }

  async getStatus(userId, { callId } = {}) {
    const uid = normalizeId(userId);
    if (!uid) return { active: false };
    const busy = await this._getBusyRaw(uid);
    const requested = normalizeId(callId);
    if (busy?.kind === 'livekit_group' && busy.ownerId) {
      const groupCall = await this.getLiveKitGroupCall(busy.ownerId);
      if (
        groupCall &&
        (!requested || requested === String(groupCall.callId))
      ) {
        return publicLiveKitGroupStatus(groupCall, uid);
      }
      if (requested) return { active: false };
    }
    const activeId = await this.getUserDmCallId(uid);
    if (!activeId || (requested && requested !== activeId)) {
      return { active: false };
    }
    const call = await this.getCall(activeId);
    if (!call || Number(call.expiresAt) <= (await this._redisNow())) {
      return { active: false };
    }
    return publicCallStatus(call, uid);
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
    const id = normalizeId(callId);
    const room = normalizeId(roomName);
    const chat = normalizeId(chatId);
    const host = normalizeId(hostId);
    if (!id || !room || !chat || !host || !Array.isArray(participants)) {
      return { ok: false, code: 'invalid_call' };
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
    if (!unique.has(host)) unique.set(host, { userId: host, label: '' });
    const participantOrder = [...unique.keys()];
    const participantMap = {};
    for (const entry of unique.values()) {
      participantMap[entry.userId] = {
        ...entry,
        state: entry.userId === host ? 'joined' : 'invited',
      };
    }
    const now = Date.now();
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
      participantOrder,
      participants: participantMap,
    };
    const groupHash = this._groupHash(id);
    const raw = await this._eval(
      CREATE_LIVEKIT_GROUP_CALL_LUA,
      [
        this._groupKeyFromHash(groupHash),
        this._tombstoneKey(id),
        this._groupRoomKey(room),
        this._chatBusyKey(chat),
        this.groupDeadlinesKey,
        ...participantOrder.map((uid) => this._busyKey(uid)),
      ],
      [
        JSON.stringify(call),
        this._groupKeyTtlMs(),
        this._groupBusyTtlMs(),
        normalizeId(instanceId) || '',
        this.config.ringingTtlMs,
        this.config.liveKitGroupCallTtlMs,
        groupHash,
      ]
    );
    return parseJson(raw, { ok: false, code: 'registry_error' });
  }

  async getLiveKitGroupCall(callId) {
    const id = normalizeId(callId);
    if (!id) return null;
    const call = parseJson(await this._get(this._groupKey(id)));
    if (!call) return null;
    if (Number(call.expiresAt) <= (await this._redisNow())) return null;
    return call;
  }

  async getLiveKitGroupCallRecord(callId) {
    const id = normalizeId(callId);
    return id ? parseJson(await this._get(this._groupKey(id))) : null;
  }

  async getLiveKitGroupCallTombstone(callId) {
    const id = normalizeId(callId);
    if (!id) return null;
    const call = parseJson(await this._get(this._tombstoneKey(id)));
    return call?.kind === 'livekit_group' ? call : null;
  }

  async getLiveKitGroupCallByRoom(roomName) {
    const room = normalizeId(roomName);
    if (!room) return null;
    const callId = await this._get(this._groupRoomKey(room));
    return callId ? this.getLiveKitGroupCall(callId) : null;
  }

  async getLiveKitGroupCallForChat(chatId) {
    const chat = normalizeId(chatId);
    if (!chat) return null;
    const busy = parseJson(await this._get(this._chatBusyKey(chat)));
    if (busy?.kind !== 'livekit_group' || !busy.ownerId) return null;
    return this.getLiveKitGroupCall(busy.ownerId);
  }

  async getUserLiveKitGroupCallId(userId) {
    const busy = await this.getBusy(userId);
    return busy?.kind === 'livekit_group' ? String(busy.ownerId) : null;
  }

  async _mutateLiveKitGroupCall(callId, operation) {
    const id = normalizeId(callId);
    if (!id) return { ok: false, code: 'call_not_found' };
    return this._withLiveKitGroupLock(id, async () => {
      const call = parseJson(await this._get(this._groupKey(id)));
      if (!call) return { ok: false, code: 'call_not_found' };
      const now = await this._redisNow();
      if (Number(call.expiresAt) <= now) {
        return { ok: false, code: 'call_expired' };
      }
      return operation(call, now);
    });
  }

  async joinLiveKitGroupCall({
    callId,
    userId,
    connId,
    answerTokenHash,
  }) {
    const uid = normalizeId(userId);
    const connectionId = normalizeId(connId);
    return this._mutateLiveKitGroupCall(callId, async (call, now) => {
      const participant = call.participants?.[uid];
      if (!participant) return { ok: false, code: 'forbidden' };
      if (connectionId) {
        const currentConnection = parseJson(
          await this._get(this._connectionKey(connectionId))
        );
        if (
          !currentConnection ||
          String(currentConnection.userId) !== uid ||
          Number(currentConnection.expiresAt) <= now
        ) {
          return { ok: false, code: 'connection_not_registered' };
        }
      }
      if (['declined', 'left', 'timed_out'].includes(participant.state)) {
        return { ok: false, code: 'invite_inactive' };
      }
      const alreadyJoined = participant.state === 'joined';
      if (
        alreadyJoined &&
        connectionId &&
        participant.answerConnId &&
        participant.answerConnId !== connectionId
      ) {
        const previousConnection = parseJson(
          await this._get(this._connectionKey(participant.answerConnId))
        );
        if (
          previousConnection &&
          String(previousConnection.userId) === uid &&
          Number(previousConnection.expiresAt) > now
        ) {
          return { ok: false, code: 'media_owned_elsewhere' };
        }
      }
      participant.state = 'joined';
      participant.joinedAt ??= now;
      if (connectionId) participant.answerConnId = connectionId;
      if (answerTokenHash) {
        participant.answerTokenHash = String(answerTokenHash);
      }
      delete participant.disconnectDeadline;
      if (uid !== String(call.hostId)) call.hadGuestJoin = true;
      call.state = 'active';
      call.updatedAt = now;
      call.expiresAt = now + this.config.liveKitGroupCallTtlMs;
      call.revision = (Number(call.revision) || 0) + 1;
      await this._persistLiveKitGroupCall(call);
      return { ok: true, alreadyJoined, call };
    });
  }

  async rejectLiveKitGroupCall({
    callId,
    userId,
    reason = 'declined',
  }) {
    const uid = normalizeId(userId);
    return this._mutateLiveKitGroupCall(callId, async (call, now) => {
      const participant = call.participants?.[uid];
      if (!participant) return { ok: false, code: 'forbidden' };
      if (uid === String(call.hostId)) {
        return { ok: false, code: 'host_cannot_reject' };
      }
      if (!['declined', 'left', 'timed_out'].includes(participant.state)) {
        participant.state = 'declined';
        participant.reason = String(reason).slice(0, 64);
        participant.leftAt = now;
        call.updatedAt = now;
        call.revision = (Number(call.revision) || 0) + 1;
        await this._releaseExact(
          this._busyKey(uid),
          'livekit_group',
          call.callId
        );
        await this._persistLiveKitGroupCall(call);
      }
      return { ok: true, call };
    });
  }

  async leaveLiveKitGroupCall({
    callId,
    userId,
    reason = 'left',
    webhook = false,
  }) {
    const uid = normalizeId(userId);
    return this._mutateLiveKitGroupCall(callId, async (call, now) => {
      const participant = call.participants?.[uid];
      if (!participant) return { ok: false, code: 'forbidden' };
      if (['left', 'declined', 'timed_out'].includes(participant.state)) {
        return { ok: true, call, alreadyLeft: true };
      }
      if (webhook) {
        participant.state = 'disconnected';
        participant.disconnectDeadline = now + this.config.disconnectGraceMs;
        call.updatedAt = now;
        call.revision = (Number(call.revision) || 0) + 1;
        await this._persistLiveKitGroupCall(call);
        return {
          ok: true,
          call,
          reconnectGrace: true,
          hostGrace: uid === String(call.hostId),
        };
      }
      participant.state = 'left';
      participant.reason = String(reason).slice(0, 64);
      participant.leftAt = now;
      await this._releaseExact(
        this._busyKey(uid),
        'livekit_group',
        call.callId
      );
      if (uid === String(call.hostId)) {
        const ended = await this._endLiveKitGroupCallLocked(
          call,
          'host_left'
        );
        return { ok: true, ended: true, call: ended };
      }
      const joinedCount = Object.values(call.participants).filter(
        (entry) => entry.state === 'joined'
      ).length;
      if (call.hadGuestJoin && joinedCount <= 1) {
        const ended = await this._endLiveKitGroupCallLocked(call, 'empty');
        return { ok: true, ended: true, call: ended };
      }
      call.updatedAt = now;
      call.revision = (Number(call.revision) || 0) + 1;
      await this._persistLiveKitGroupCall(call);
      return { ok: true, call };
    });
  }

  async finishLiveKitGroupCall({ callId, reason = 'ended' }) {
    const id = normalizeId(callId);
    if (!id) return { ok: false, code: 'call_not_found' };
    return this._withLiveKitGroupLock(id, async () => {
      const call = parseJson(await this._get(this._groupKey(id)));
      if (!call) {
        const tombstone = parseJson(await this._get(this._tombstoneKey(id)));
        return tombstone
          ? { ok: true, alreadyEnded: true, call: tombstone }
          : { ok: false, code: 'call_not_found' };
      }
      const ended = await this._endLiveKitGroupCallLocked(call, reason);
      return { ok: true, ended: true, call: ended };
    });
  }

  async claimLiveKitWebhookEvent(
    eventId,
    ttlMs = this.config.tombstoneTtlMs
  ) {
    const id = normalizeId(eventId);
    if (!id) return false;
    this._requireReady();
    const result = await this._runCommand(
      this.client.set(this._webhookEventKey(id), '1', {
        NX: true,
        PX: ttlMs,
      })
    );
    return result === 'OK';
  }

  async acquireChatBusy({ chatId, kind, ownerId, instanceId }) {
    const chat = normalizeId(chatId);
    const owner = normalizeId(ownerId);
    if (!chat || !owner || !kind) {
      return { ok: false, code: 'invalid_chat_busy' };
    }
    const busy = {
      kind: String(kind),
      ownerId: owner,
      instanceId: normalizeId(instanceId),
    };
    const raw = await this._eval(
      ACQUIRE_BUSY_LUA,
      [this._chatBusyKey(chat)],
      [busy.kind, owner, JSON.stringify(busy), this._busyTtlMs()]
    );
    const result = parseJson(raw, { ok: false, code: 'registry_error' });
    return result.code === 'busy'
      ? { ...result, code: 'chat_call_active' }
      : result;
  }

  async releaseChatBusy({ chatId, kind, ownerId }) {
    const chat = normalizeId(chatId);
    const owner = normalizeId(ownerId);
    if (!chat || !owner) return false;
    return this._releaseExact(this._chatBusyKey(chat), kind, owner);
  }

  async getChatBusy(chatId) {
    const chat = normalizeId(chatId);
    if (!chat) return null;
    return parseJson(await this._get(this._chatBusyKey(chat)));
  }

  async _mutate(op, { callId, userId, connId, mediaType, reason }) {
    const call = await this.getCall(callId);
    if (!call) return { ok: false, code: 'call_not_found' };
    const uid = normalizeId(userId) || '';
    const cid = normalizeId(connId) || '';
    const connHash = cid ? this._connHash(cid) : '';
    const callHash = this._callHash(call.callId);
    const raw = await this._eval(
      MUTATE_DM_CALL_LUA,
      [
        this._callKeyFromHash(callHash),
        this._tombstoneKey(call.callId),
        this._busyKey(call.callerId),
        this._busyKey(call.calleeId),
        this.deadlinesKey,
        cid
          ? this._connectionKeyFromHash(connHash)
          : this._dummyConnectionKey(`${call.callId}:${uid}`),
      ],
      [
        op,
        Date.now(),
        uid,
        cid,
        connHash,
        mediaType || '',
        reason || 'ended',
        this.config.acceptedTtlMs,
        this._callKeyTtlMs(),
        this._busyTtlMs(),
        this.config.tombstoneTtlMs,
        this.config.connectionLeaseMs,
        callHash,
        `${this.prefix}conn:`,
      ]
    );
    return parseJson(raw, { ok: false, code: 'registry_error' });
  }

  async acceptDmCall(input) {
    return this._mutate('accept', input);
  }

  async resumeDmCall(input) {
    const result = await this._mutate('resume', input);
    return {
      ...result,
      status: result.call
        ? publicCallStatus(result.call, input.userId)
        : { active: false },
    };
  }

  async authorizeMedia(input) {
    return this._mutate('media', input);
  }

  async terminateDmCall({
    callId,
    userId,
    connId,
    reason = 'ended',
    ringingOnly = false,
  }) {
    return this._mutate(ringingOnly ? 'reject' : 'terminate', {
      callId,
      userId,
      connId,
      reason,
    });
  }

  async registerConnection({ userId, connId, instanceId }) {
    const uid = normalizeId(userId);
    const cid = normalizeId(connId);
    if (!uid || !cid) return false;
    const now = Date.now();
    const lease = {
      userId: uid,
      connId: cid,
      instanceId: normalizeId(instanceId),
      expiresAt: now + this.config.connectionLeaseMs,
    };
    const result = await this._eval(
      REGISTER_CONNECTION_LUA,
      [this._connectionKey(cid)],
      [uid, JSON.stringify(lease), this.config.connectionLeaseMs]
    );
    return Number(result) === 1;
  }

  async heartbeatConnection({ userId, connId, instanceId }) {
    const uid = normalizeId(userId);
    const cid = normalizeId(connId);
    if (!uid || !cid) return false;
    const busy = await this._getBusyRaw(uid);
    const callHash =
      busy?.kind === 'dm' && busy.callHash
        ? String(busy.callHash)
        : this._hash(`no-call:${uid}`);
    const raw = await this._eval(
      HEARTBEAT_CONNECTION_LUA,
      [
        this._connectionKey(cid),
        this._busyKey(uid),
        this._callKeyFromHash(callHash),
        this.deadlinesKey,
      ],
      [
        uid,
        normalizeId(instanceId) || '',
        Date.now(),
        this.config.connectionLeaseMs,
        this.config.busyLeaseMs,
        cid,
        this.config.acceptedTtlMs,
        this._callKeyTtlMs(),
        this._busyTtlMs(),
        callHash,
      ]
    );
    const refreshed = Number(raw) === 1;
    if (refreshed && busy?.kind === 'livekit_group' && busy.ownerId) {
      await this._mutateLiveKitGroupCall(
        busy.ownerId,
        async (call, now) => {
          const participant = call.participants?.[uid];
          if (
            participant &&
            ['joined', 'disconnected'].includes(participant.state)
          ) {
            call.expiresAt = now + this.config.liveKitGroupCallTtlMs;
            call.updatedAt = now;
            call.revision = (Number(call.revision) || 0) + 1;
            await this._persistLiveKitGroupCall(call);
          }
          return { ok: true };
        }
      );
    }
    return refreshed;
  }

  async unregisterConnection({ userId, connId }) {
    const uid = normalizeId(userId);
    const cid = normalizeId(connId);
    if (!uid || !cid) return { wasMedia: false, call: null };
    const busy = await this._getBusyRaw(uid);
    const callHash =
      busy?.kind === 'dm' && busy.callHash
        ? String(busy.callHash)
        : this._hash(`no-call:${uid}`);
    const raw = await this._eval(
      UNREGISTER_CONNECTION_LUA,
      [
        this._connectionKey(cid),
        this._busyKey(uid),
        this._callKeyFromHash(callHash),
        this.deadlinesKey,
      ],
      [
        uid,
        cid,
        Date.now(),
        this.config.disconnectGraceMs,
        this.config.ringingDisconnectGraceMs,
        this._callKeyTtlMs(),
        callHash,
      ]
    );
    return parseJson(raw, { wasMedia: false, call: null });
  }

  async acquireBusy({ userId, kind, ownerId, instanceId }) {
    const uid = normalizeId(userId);
    const owner = normalizeId(ownerId);
    if (!uid || !owner || !kind) return { ok: false, code: 'invalid_busy' };
    const existing = await this._getBusyRaw(uid);
    if (existing?.kind === 'dm') {
      await this.getUserDmCallId(uid);
    }
    const busy = {
      kind: String(kind),
      ownerId: owner,
      instanceId: normalizeId(instanceId),
    };
    const raw = await this._eval(
      ACQUIRE_BUSY_LUA,
      [this._busyKey(uid)],
      [busy.kind, owner, JSON.stringify(busy), this.config.busyLeaseMs]
    );
    return parseJson(raw, { ok: false, code: 'registry_error' });
  }

  async releaseBusy({ userId, kind, ownerId }) {
    const uid = normalizeId(userId);
    const owner = normalizeId(ownerId);
    if (!uid || !owner) return false;
    const raw = await this._eval(
      RELEASE_BUSY_LUA,
      [this._busyKey(uid)],
      [String(kind), owner]
    );
    return Number(raw) === 1;
  }

  async getBusy(userId) {
    const uid = normalizeId(userId);
    if (!uid) return null;
    return this._getBusyRaw(uid);
  }

  async heartbeatInstance(instanceId) {
    const id = normalizeId(instanceId);
    if (!id) return false;
    this._requireReady();
    try {
      await this._runCommand(
        this.client.set(
          `${this.prefix}instance:${this._hash(id)}`,
          JSON.stringify({ instanceId: id, updatedAt: Date.now() }),
          { PX: this.config.instanceLeaseMs }
        )
      );
      return true;
    } catch (error) {
      throw new RealtimeUnavailableError('realtime_redis_command_failed', {
        cause: error,
      });
    }
  }

  async _sweepCall(callHash, suppliedCall = null) {
    const call = suppliedCall || (await this._readCallByHash(callHash));
    if (!call) {
      this._requireReady();
      try {
        await this._runCommand(
          this.client.zRem(this.deadlinesKey, callHash)
        );
      } catch (error) {
        throw new RealtimeUnavailableError('realtime_redis_command_failed', {
          cause: error,
        });
      }
      return null;
    }
    const callerBinding = call.media?.[String(call.callerId)];
    const calleeBinding = call.media?.[String(call.calleeId)];
    const raw = await this._eval(
      SWEEP_DM_CALL_LUA,
      [
        this._callKeyFromHash(callHash),
        this._tombstoneKey(call.callId),
        this._busyKey(call.callerId),
        this._busyKey(call.calleeId),
        this.deadlinesKey,
        callerBinding?.connHash
          ? this._connectionKeyFromHash(callerBinding.connHash)
          : this._dummyConnectionKey(`${callHash}:caller`),
        calleeBinding?.connHash
          ? this._connectionKeyFromHash(calleeBinding.connHash)
          : this._dummyConnectionKey(`${callHash}:callee`),
      ],
      [
        callHash,
        Date.now(),
        this.config.disconnectGraceMs,
        this.config.ringingDisconnectGraceMs,
        this._callKeyTtlMs(),
        this.config.tombstoneTtlMs,
        callerBinding?.connHash || '',
        calleeBinding?.connHash || '',
      ]
    );
    return parseJson(raw)?.ended || null;
  }

  async _sweepLiveKitGroup(groupHash) {
    const initial = parseJson(
      await this._get(this._groupKeyFromHash(groupHash))
    );
    if (!initial) {
      await this._runCommand(
        this.client.zRem(this.groupDeadlinesKey, groupHash)
      );
      return null;
    }
    return this._withLiveKitGroupLock(initial.callId, async () => {
      const call = parseJson(
        await this._get(this._groupKeyFromHash(groupHash))
      );
      if (!call) return null;
      const now = await this._redisNow();
      let reason = null;
      let changed = false;
      for (const uid of call.participantOrder || []) {
        const participant = call.participants?.[uid];
        if (
          participant?.state !== 'disconnected' ||
          Number(participant.disconnectDeadline) > now
        ) {
          continue;
        }
        if (String(uid) === String(call.hostId)) {
          reason = 'host_disconnected';
          break;
        }
        participant.state = 'left';
        participant.leftAt = now;
        delete participant.disconnectDeadline;
        await this._releaseExact(
          this._busyKey(uid),
          'livekit_group',
          call.callId
        );
        changed = true;
      }
      if (!reason && changed) {
        const joinedCount = Object.values(call.participants).filter(
          (entry) => entry.state === 'joined'
        ).length;
        if (call.hadGuestJoin && joinedCount <= 1) reason = 'empty';
      }
      if (
        !reason &&
        !call.hadGuestJoin &&
        Number(call.ringingExpiresAt) <= now
      ) {
        reason = 'no_answer';
      } else if (!reason && Number(call.expiresAt) <= now) {
        reason = 'call_ttl';
      }
      if (reason) {
        return this._endLiveKitGroupCallLocked(call, reason);
      }

      if (Number(call.ringingExpiresAt) <= now) {
        for (const uid of call.participantOrder || []) {
          const participant = call.participants?.[uid];
          if (participant?.state !== 'invited') continue;
          participant.state = 'timed_out';
          participant.leftAt = now;
          await this._releaseExact(
            this._busyKey(uid),
            'livekit_group',
            call.callId
          );
          changed = true;
        }
      }
      if (changed) {
        call.updatedAt = now;
        call.revision = (Number(call.revision) || 0) + 1;
      }
      await this._persistLiveKitGroupCall(call);
      return null;
    });
  }

  async sweepExpired() {
    this._requireReady();
    let hashes;
    try {
      hashes = await this._runCommand(
        this.client.zRangeByScore(
          this.deadlinesKey,
          0,
          await this._redisNow(),
          { LIMIT: { offset: 0, count: 100 } }
        )
      );
    } catch (error) {
      throw new RealtimeUnavailableError('realtime_redis_command_failed', {
        cause: error,
      });
    }
    const ended = [];
    for (const hash of hashes) {
      const call = await this._sweepCall(hash);
      if (call) ended.push(call);
    }
    let groupHashes;
    try {
      groupHashes = await this._runCommand(
        this.client.zRangeByScore(
          this.groupDeadlinesKey,
          0,
          await this._redisNow(),
          { LIMIT: { offset: 0, count: 100 } }
        )
      );
    } catch (error) {
      throw new RealtimeUnavailableError('realtime_redis_command_failed', {
        cause: error,
      });
    }
    for (const hash of groupHashes) {
      const call = await this._sweepLiveKitGroup(hash);
      if (call?.kind === 'livekit_group') ended.push(call);
    }
    return ended;
  }
}
