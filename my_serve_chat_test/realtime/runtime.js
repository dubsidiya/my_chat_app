import crypto from 'node:crypto';
import { createClient } from 'redis';

import { loadRealtimeConfig } from './config.js';
import { RealtimeUnavailableError } from './errors.js';
import { MemoryCallRegistry } from './memoryCallRegistry.js';
import { RedisCallRegistry } from './redisCallRegistry.js';

const MAX_DELIVERY_BYTES = 80 * 1024;

function normalizeId(value) {
  const id = value?.toString().trim();
  return id || null;
}

function isRealtimePayloadType(value) {
  return (
    typeof value === 'string' &&
    (value.startsWith('call_') ||
      value.startsWith('gcall_') ||
      value.startsWith('lkcall_'))
  );
}

function safeTelemetry(enabled, event, fields = {}) {
  if (!enabled) return;
  const allowed = {};
  for (const [key, value] of Object.entries(fields)) {
    if (
      [
        'mode',
        'ready',
        'reason',
        'operation',
        'count',
        'state',
        'kind',
      ].includes(key)
    ) {
      allowed[key] = value;
    }
  }
  console.log(
    JSON.stringify({
      component: 'realtime',
      event,
      ...allowed,
      ts: new Date().toISOString(),
    })
  );
}

export class RealtimeRuntime {
  constructor(config = loadRealtimeConfig()) {
    this.config = config;
    this.instanceId = config.instanceId || crypto.randomUUID();
    this._registry =
      config.mode === 'memory' ? new MemoryCallRegistry(config) : null;
    this._command = null;
    this._publisher = null;
    this._subscriber = null;
    this._subscribed = false;
    this._started = false;
    this._stopping = false;
    this._connecting = null;
    this._retryTimer = null;
    this._sweepTimer = null;
    this._instanceTimer = null;
    this._localDelivery = null;
    this._liveKitGroupEnded = null;
    this._seenDeliveryIds = new Map();
    this._deliveryChannel = `rt:{${config.namespace}}:v1:delivery`;
  }

  get registry() {
    if (
      !this._registry ||
      (this.config.mode === 'redis' && !this.isReady())
    ) {
      throw new RealtimeUnavailableError();
    }
    return this._registry;
  }

  setLocalDelivery(handler) {
    this._localDelivery = typeof handler === 'function' ? handler : null;
  }

  setLiveKitGroupEndedHandler(handler) {
    this._liveKitGroupEnded =
      typeof handler === 'function' ? handler : null;
  }

  isReady() {
    if (this.config.mode === 'memory') {
      return Boolean(this._registry?.isReady());
    }
    return Boolean(
      this._registry?.isReady() &&
        this._publisher?.isReady &&
        this._subscriber?.isReady &&
        this._subscribed
    );
  }

  readiness() {
    return {
      ready: this.isReady(),
      mode: this.config.mode,
    };
  }

  telemetry(event, fields = {}) {
    safeTelemetry(this.config.telemetryEnabled, event, {
      mode: this.config.mode,
      ...fields,
    });
  }

  async start() {
    if (this._started) return this.isReady();
    this._started = true;
    this._stopping = false;
    if (this.config.mode === 'memory') {
      await this._registry.start();
      this._startMaintenance();
      safeTelemetry(this.config.telemetryEnabled, 'started', {
        mode: 'memory',
        ready: true,
      });
      return true;
    }

    try {
      await this._connectRedis();
    } catch (error) {
      safeTelemetry(this.config.telemetryEnabled, 'connect_failed', {
        mode: 'redis',
        ready: false,
        reason: error?.code || error?.name || 'error',
      });
      this._scheduleReconnect();
    }
    this._startMaintenance();
    return this.isReady();
  }

  _redisOptions() {
    return {
      url: this.config.redisUrl,
      socket: {
        connectTimeout: this.config.redisConnectTimeoutMs,
        reconnectStrategy: false,
      },
    };
  }

  async _runRedisCommand(client, command) {
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
          client?.destroy();
        } catch {}
      }
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }

  _wireClient(client, kind) {
    client.on('error', (error) => {
      safeTelemetry(this.config.telemetryEnabled, 'client_error', {
        mode: 'redis',
        kind,
        reason: error?.code || error?.name || 'error',
      });
    });
    client.on('end', () => {
      if (!this._stopping) {
        this._subscribed = false;
        safeTelemetry(this.config.telemetryEnabled, 'disconnected', {
          mode: 'redis',
          kind,
          ready: false,
          reason: 'connection_end',
        });
        this._scheduleReconnect();
      }
    });
  }

  async _connectRedis() {
    if (this._stopping) return;
    if (this._connecting) return this._connecting;
    this._connecting = (async () => {
      await this._closeRedisClients();
      const command = createClient(this._redisOptions());
      const publisher = command.duplicate();
      const subscriber = command.duplicate();
      this._wireClient(command, 'command');
      this._wireClient(publisher, 'publisher');
      this._wireClient(subscriber, 'subscriber');
      this._command = command;
      this._publisher = publisher;
      this._subscriber = subscriber;
      this._registry = new RedisCallRegistry(this.config, command);

      try {
        await Promise.all([
          command.connect(),
          publisher.connect(),
          subscriber.connect(),
        ]);
        await this._runRedisCommand(
          subscriber,
          subscriber.subscribe(this._deliveryChannel, (raw) => {
            this._handleDelivery(raw);
          })
        );
        this._subscribed = true;
        await this._registry.heartbeatInstance(this.instanceId);
        safeTelemetry(this.config.telemetryEnabled, 'connected', {
          mode: 'redis',
          ready: true,
        });
      } catch (error) {
        this._subscribed = false;
        await this._closeRedisClients();
        throw new RealtimeUnavailableError('realtime_redis_connect_failed', {
          cause: error,
        });
      }
    })();
    try {
      await this._connecting;
    } finally {
      this._connecting = null;
    }
  }

  _scheduleReconnect() {
    if (
      this.config.mode !== 'redis' ||
      this._stopping ||
      this._retryTimer ||
      this._connecting
    ) {
      return;
    }
    this._retryTimer = setTimeout(() => {
      this._retryTimer = null;
      this._connectRedis().catch((error) => {
        safeTelemetry(this.config.telemetryEnabled, 'reconnect_failed', {
          mode: 'redis',
          ready: false,
          reason: error?.code || error?.name || 'error',
        });
        this._scheduleReconnect();
      });
    }, this.config.redisRetryMs);
    this._retryTimer.unref?.();
  }

  _startMaintenance() {
    if (!this._sweepTimer) {
      this._sweepTimer = setInterval(() => {
        this._sweep().catch((error) => {
          safeTelemetry(this.config.telemetryEnabled, 'sweep_failed', {
            mode: this.config.mode,
            reason: error?.code || error?.name || 'error',
          });
        });
      }, this.config.sweepIntervalMs);
      this._sweepTimer.unref?.();
    }
    if (!this._instanceTimer) {
      const interval = Math.max(
        1_000,
        Math.floor(this.config.instanceLeaseMs / 3)
      );
      this._instanceTimer = setInterval(() => {
        if (this.config.mode !== 'redis' || !this.isReady()) return;
        this.registry.heartbeatInstance(this.instanceId).catch(() => {});
      }, interval);
      this._instanceTimer.unref?.();
    }
  }

  async _sweep() {
    if (!this.isReady()) return;
    const ended = await this.registry.sweepExpired();
    for (const call of ended) {
      if (call.kind === 'livekit_group') {
        await this._liveKitGroupEnded?.(call);
        const payload = {
          type: 'lkcall_ended',
          call_id: call.callId,
          chat_id: call.chatId,
          reason: call.reason || 'ended',
          ts: new Date().toISOString(),
        };
        await Promise.allSettled(
          (call.participantOrder || []).map((userId) =>
            this.deliver(userId, payload)
          )
        );
        continue;
      }
      const base = {
        type: 'call_hangup',
        call_id: call.callId,
        chat_id: call.chatId,
        reason: call.reason || 'ended',
        ts: new Date().toISOString(),
      };
      await Promise.allSettled([
        this.deliver(call.callerId, {
          ...base,
          from_user_id: call.calleeId,
        }),
        this.deliver(call.calleeId, {
          ...base,
          from_user_id: call.callerId,
        }),
      ]);
    }
    if (ended.length > 0) {
      safeTelemetry(this.config.telemetryEnabled, 'calls_expired', {
        mode: this.config.mode,
        count: ended.length,
      });
    }
  }

  async deliver(userId, payload, { connId, excludeConnId } = {}) {
    const uid = normalizeId(userId);
    if (!uid || !payload || typeof payload !== 'object') return false;
    const payloadType = payload.type?.toString();
    if (!isRealtimePayloadType(payloadType)) {
      return false;
    }
    const envelope = {
      version: 1,
      eventId: crypto.randomUUID(),
      publishedAt: Date.now(),
      userId: uid,
      connId: normalizeId(connId),
      excludeConnId: normalizeId(excludeConnId),
      payload,
    };
    const encoded = JSON.stringify(envelope);
    if (Buffer.byteLength(encoded) > MAX_DELIVERY_BYTES) return false;

    if (this.config.mode === 'memory') {
      if (!this.isReady()) throw new RealtimeUnavailableError();
      this._localDelivery?.(envelope);
      return true;
    }
    if (!this.isReady()) throw new RealtimeUnavailableError();
    try {
      await this._runRedisCommand(
        this._publisher,
        this._publisher.publish(this._deliveryChannel, encoded)
      );
      return true;
    } catch (error) {
      throw new RealtimeUnavailableError('realtime_delivery_failed', {
        cause: error,
      });
    }
  }

  _handleDelivery(raw) {
    if (typeof raw !== 'string' || Buffer.byteLength(raw) > MAX_DELIVERY_BYTES) {
      return;
    }
    let envelope;
    try {
      envelope = JSON.parse(raw);
    } catch {
      return;
    }
    if (
      envelope?.version !== 1 ||
      !normalizeId(envelope.eventId) ||
      !normalizeId(envelope.userId) ||
      !envelope.payload ||
      typeof envelope.payload !== 'object' ||
      !isRealtimePayloadType(envelope.payload.type)
    ) {
      return;
    }
    if (this._seenDeliveryIds.has(envelope.eventId)) return;
    this._seenDeliveryIds.set(envelope.eventId, Date.now());
    if (this._seenDeliveryIds.size > 512) {
      const oldest = this._seenDeliveryIds.keys().next().value;
      this._seenDeliveryIds.delete(oldest);
    }
    this._localDelivery?.(envelope);
  }

  async _closeClient(client) {
    if (!client) return;
    try {
      if (client.isOpen) await client.close();
    } catch {
      try {
        client.destroy();
      } catch {}
    }
  }

  async _closeRedisClients() {
    const clients = [this._subscriber, this._publisher, this._command];
    this._subscriber = null;
    this._publisher = null;
    this._command = null;
    this._subscribed = false;
    await Promise.allSettled(clients.map((client) => this._closeClient(client)));
  }

  async stop() {
    if (this._stopping) return;
    this._stopping = true;
    this._retryTimer && clearTimeout(this._retryTimer);
    this._sweepTimer && clearInterval(this._sweepTimer);
    this._instanceTimer && clearInterval(this._instanceTimer);
    this._retryTimer = null;
    this._sweepTimer = null;
    this._instanceTimer = null;
    if (this.config.mode === 'memory') {
      await this._registry?.stop();
    } else {
      await this._closeRedisClients();
    }
    this._started = false;
    this._seenDeliveryIds.clear();
    this._liveKitGroupEnded = null;
    safeTelemetry(this.config.telemetryEnabled, 'stopped', {
      mode: this.config.mode,
      ready: false,
    });
  }
}

export function createRealtimeRuntime(config = loadRealtimeConfig()) {
  return new RealtimeRuntime(config);
}
