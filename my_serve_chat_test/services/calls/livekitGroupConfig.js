import crypto from 'node:crypto';

const TRUE_VALUES = new Set(['1', 'true', 'yes', 'on']);

function parseBoolean(raw, fallback = false) {
  if (raw == null || String(raw).trim() === '') return fallback;
  return TRUE_VALUES.has(String(raw).trim().toLowerCase());
}

function parseInteger(raw, fallback, { min, max, name }) {
  if (raw == null || String(raw).trim() === '') return fallback;
  const value = Number.parseInt(String(raw), 10);
  if (!Number.isSafeInteger(value) || value < min || value > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}`);
  }
  return value;
}

function parseChoice(raw, fallback, choices, name) {
  const value = String(raw || fallback).trim().toLowerCase();
  if (!choices.includes(value)) {
    throw new Error(`${name} must be one of: ${choices.join(', ')}`);
  }
  return value;
}

function parseDeploymentId(raw) {
  const value = String(raw || 'local').trim().toLowerCase();
  if (!/^[a-z0-9-]{1,24}$/.test(value)) {
    throw new Error('LIVEKIT_DEPLOYMENT_ID must match [a-z0-9-]{1,24}');
  }
  return value;
}

function parseVersion(raw) {
  const match = String(raw || '')
    .trim()
    .match(/^(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$/);
  return match ? match.slice(1).map(Number) : null;
}

export function compareAppVersions(left, right) {
  const a = parseVersion(left);
  const b = parseVersion(right);
  if (!a || !b) return null;
  for (let index = 0; index < 3; index += 1) {
    if (a[index] !== b[index]) return a[index] < b[index] ? -1 : 1;
  }
  return 0;
}

export function stableLiveKitBucket(deploymentId, chatId) {
  const digest = crypto
    .createHash('sha256')
    .update(`${deploymentId}:${String(chatId)}`)
    .digest();
  return digest.readUInt32BE(0) % 100;
}

export function loadLiveKitGroupConfig(env = process.env) {
  const nodeEnv = String(env.NODE_ENV || 'development').trim().toLowerCase();
  const provider = parseChoice(
    env.LIVEKIT_GROUP_PROVIDER,
    'livekit',
    ['livekit', 'fake'],
    'LIVEKIT_GROUP_PROVIDER'
  );
  if (provider === 'fake' && nodeEnv === 'production') {
    throw new Error('LIVEKIT_GROUP_PROVIDER=fake is not allowed in production');
  }

  const defaultTransport = parseChoice(
    env.GROUP_CALL_DEFAULT_TRANSPORT,
    'mesh',
    ['mesh', 'livekit'],
    'GROUP_CALL_DEFAULT_TRANSPORT'
  );
  const rolloutPercent = parseInteger(
    env.GROUP_CALL_LIVEKIT_ROLLOUT_PERCENT,
    0,
    {
      min: 0,
      max: 100,
      name: 'GROUP_CALL_LIVEKIT_ROLLOUT_PERCENT',
    }
  );
  const explicitlyEnabled = parseBoolean(
    env.LIVEKIT_GROUP_FEATURE_ENABLED,
    false
  );
  const requested =
    explicitlyEnabled ||
    provider === 'fake' ||
    defaultTransport === 'livekit' ||
    rolloutPercent > 0;

  const url = String(env.LIVEKIT_URL || '').trim();
  const apiKey = String(env.LIVEKIT_API_KEY || '').trim();
  const apiSecret = String(env.LIVEKIT_API_SECRET || '').trim();
  const hasCredentials = Boolean(url && apiKey && apiSecret);
  if (requested && provider === 'livekit' && !hasCredentials) {
    throw new Error(
      'LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET are required when LiveKit rollout is enabled'
    );
  }

  return Object.freeze({
    nodeEnv,
    provider,
    requested,
    enabled: requested && (provider === 'fake' || hasCredentials),
    defaultTransport,
    rolloutPercent,
    deploymentId: parseDeploymentId(env.LIVEKIT_DEPLOYMENT_ID),
    minAppVersion: String(env.LIVEKIT_GROUP_MIN_APP_VERSION || '').trim(),
    url,
    apiKey,
    apiSecret,
    hasCredentials,
    maxParticipants: parseInteger(
      env.LIVEKIT_GROUP_MAX_PARTICIPANTS,
      4,
      {
        min: 2,
        max: 32,
        name: 'LIVEKIT_GROUP_MAX_PARTICIPANTS',
      }
    ),
    tokenTtlSeconds: parseInteger(env.LIVEKIT_TOKEN_TTL_SECONDS, 3600, {
      min: 60,
      max: 24 * 60 * 60,
      name: 'LIVEKIT_TOKEN_TTL_SECONDS',
    }),
    roomEmptyTimeoutSeconds: parseInteger(
      env.LIVEKIT_ROOM_EMPTY_TIMEOUT_SECONDS,
      60,
      {
        min: 10,
        max: 30 * 60,
        name: 'LIVEKIT_ROOM_EMPTY_TIMEOUT_SECONDS',
      }
    ),
    webhookEnabled: parseBoolean(env.LIVEKIT_WEBHOOK_ENABLED, requested),
  });
}

export function selectGroupTransport(
  { chatId, protocolVersion, appVersion },
  config
) {
  if (Number(protocolVersion) < 2 || !config.enabled) return 'mesh';
  if (config.minAppVersion) {
    const comparison = compareAppVersions(appVersion, config.minAppVersion);
    if (comparison == null || comparison < 0) return 'mesh';
  }
  if (config.defaultTransport === 'livekit') return 'livekit';
  return stableLiveKitBucket(config.deploymentId, chatId) <
    config.rolloutPercent
    ? 'livekit'
    : 'mesh';
}

export function buildLiveKitRoomName(config, callId) {
  const compactId = String(callId).replaceAll('-', '').toLowerCase();
  return `reollity-${config.deploymentId}-g-${compactId}`.slice(0, 96);
}
