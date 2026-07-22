const TRUE_VALUES = new Set(['1', 'true', 'yes', 'on']);

function parseInteger(raw, fallback, { min, max, name }) {
  if (raw == null || String(raw).trim() === '') return fallback;
  const parsed = Number.parseInt(String(raw), 10);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}`);
  }
  return parsed;
}

function parseMode(raw, nodeEnv, hasRedisUrl) {
  const defaultMode =
    nodeEnv === 'production' || hasRedisUrl ? 'redis' : 'memory';
  const value = String(raw || defaultMode)
    .trim()
    .toLowerCase();
  if (value !== 'memory' && value !== 'redis') {
    throw new Error('REALTIME_MODE must be "memory" or "redis"');
  }
  if (nodeEnv === 'production' && value !== 'redis') {
    throw new Error('REALTIME_MODE=redis is required in production');
  }
  return value;
}

function parseNamespace(raw) {
  const value = String(raw || 'my-chat')
    .trim()
    .toLowerCase();
  if (!/^[a-z0-9_-]{1,40}$/.test(value)) {
    throw new Error('REDIS_SIGNALING_NAMESPACE must match [a-z0-9_-]{1,40}');
  }
  return value;
}

export function loadRealtimeConfig(env = process.env) {
  const nodeEnv = String(env.NODE_ENV || 'development').trim().toLowerCase();
  const redisUrl = String(env.REDIS_URL || '').trim();
  const mode = parseMode(
    env.CALL_REGISTRY_MODE ?? env.REALTIME_MODE,
    nodeEnv,
    redisUrl.length > 0
  );
  if (mode === 'redis' && !redisUrl) {
    throw new Error('REDIS_URL is required when REALTIME_MODE=redis');
  }

  const wsHeartbeatMs = parseInteger(env.WS_HEARTBEAT_MS, 10_000, {
    min: 5_000,
    max: 60_000,
    name: 'WS_HEARTBEAT_MS',
  });
  const connectionLeaseMs = parseInteger(
    env.WS_CONNECTION_LEASE_MS ?? env.CALL_CONNECTION_LEASE_MS,
    45_000,
    {
      min: 15_000,
      max: 120_000,
      name: 'WS_CONNECTION_LEASE_MS',
    }
  );
  const instanceLeaseMs = parseInteger(
    env.WS_INSTANCE_LEASE_MS ?? env.CALL_INSTANCE_LEASE_MS,
    30_000,
    {
      min: 10_000,
      max: 120_000,
      name: 'WS_INSTANCE_LEASE_MS',
    }
  );
  if (
    connectionLeaseMs < wsHeartbeatMs * 2 ||
    instanceLeaseMs < wsHeartbeatMs * 2
  ) {
    throw new Error(
      'WS connection and instance leases must be at least two heartbeat intervals'
    );
  }
  const disconnectGraceMs = parseInteger(
    env.CALL_ACCEPTED_DISCONNECT_GRACE_MS ?? env.CALL_DISCONNECT_GRACE_MS,
    15_000,
    {
      min: 2_000,
      max: 120_000,
      name: 'CALL_ACCEPTED_DISCONNECT_GRACE_MS',
    }
  );
  const ringingTtlMs = parseInteger(env.CALL_RINGING_TTL_MS, 75_000, {
    min: 10_000,
    max: 300_000,
    name: 'CALL_RINGING_TTL_MS',
  });
  const ringingDisconnectGraceMs = parseInteger(
    env.CALL_RINGING_DISCONNECT_GRACE_MS,
    3_000,
    {
      min: 500,
      max: 30_000,
      name: 'CALL_RINGING_DISCONNECT_GRACE_MS',
    }
  );
  const busyLeaseMs = parseInteger(
    env.CALL_BUSY_LEASE_MS,
    Math.max(
      connectionLeaseMs + disconnectGraceMs,
      ringingTtlMs + ringingDisconnectGraceMs
    ),
    {
      min: 30_000,
      max: 10 * 60 * 1000,
      name: 'CALL_BUSY_LEASE_MS',
    }
  );
  if (busyLeaseMs < ringingTtlMs + ringingDisconnectGraceMs) {
    throw new Error(
      'CALL_BUSY_LEASE_MS must cover ringing TTL and disconnect grace'
    );
  }
  const acceptedTtlMs = parseInteger(
    env.CALL_ACCEPTED_TTL_MS,
    busyLeaseMs,
    {
      min: 30_000,
      max: 7 * 24 * 60 * 60 * 1000,
      name: 'CALL_ACCEPTED_TTL_MS',
    }
  );
  if (acceptedTtlMs > busyLeaseMs) {
    throw new Error(
      'CALL_BUSY_LEASE_MS must be at least CALL_ACCEPTED_TTL_MS'
    );
  }

  return Object.freeze({
    mode,
    redisUrl,
    namespace: parseNamespace(
      env.REDIS_KEY_PREFIX ?? env.REDIS_SIGNALING_NAMESPACE
    ),
    instanceId: String(env.REALTIME_INSTANCE_ID || '').trim() || null,
    ringingTtlMs,
    acceptedTtlMs,
    liveKitGroupCallTtlMs: parseInteger(
      env.LIVEKIT_GROUP_CALL_TTL_MS,
      4 * 60 * 60 * 1000,
      {
        min: 60_000,
        max: 24 * 60 * 60 * 1000,
        name: 'LIVEKIT_GROUP_CALL_TTL_MS',
      }
    ),
    tombstoneTtlMs: parseInteger(
      env.CALL_TERMINAL_TTL_MS ?? env.CALL_TOMBSTONE_TTL_MS,
      300_000,
      {
        min: 30_000,
        max: 60 * 60 * 1000,
        name: 'CALL_TERMINAL_TTL_MS',
      }
    ),
    wsHeartbeatMs,
    connectionLeaseMs,
    instanceLeaseMs,
    disconnectGraceMs,
    ringingDisconnectGraceMs,
    busyLeaseMs,
    sweepIntervalMs: parseInteger(
      env.CALL_CLEANUP_INTERVAL_MS ?? env.CALL_SWEEP_INTERVAL_MS,
      1_000,
      {
        min: 250,
        max: 15_000,
        name: 'CALL_CLEANUP_INTERVAL_MS',
      }
    ),
    redisConnectTimeoutMs: parseInteger(env.REDIS_CONNECT_TIMEOUT_MS, 5_000, {
      min: 500,
      max: 30_000,
      name: 'REDIS_CONNECT_TIMEOUT_MS',
    }),
    redisCommandTimeoutMs: parseInteger(
      env.REDIS_COMMAND_TIMEOUT_MS,
      1_000,
      {
        min: 100,
        max: 10_000,
        name: 'REDIS_COMMAND_TIMEOUT_MS',
      }
    ),
    redisRetryMs: parseInteger(env.REDIS_RETRY_MS, 5_000, {
      min: 1_000,
      max: 60_000,
      name: 'REDIS_RETRY_MS',
    }),
    telemetryEnabled:
      env.REALTIME_TELEMETRY == null ||
      TRUE_VALUES.has(String(env.REALTIME_TELEMETRY).trim().toLowerCase()),
  });
}
