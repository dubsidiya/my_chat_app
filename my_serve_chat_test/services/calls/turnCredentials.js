import crypto from 'node:crypto';

const DEFAULT_STUN = 'stun:stun.l.google.com:19302';
const DEFAULT_TTL_SECONDS = 6 * 60 * 60; // 6h — matches long-call refresh window
const MIN_TTL_SECONDS = 300;
const MAX_TTL_SECONDS = 24 * 60 * 60;

function splitCsv(raw) {
  return String(raw || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

function clampTtl(raw) {
  const value = Number(raw);
  if (!Number.isFinite(value)) return DEFAULT_TTL_SECONDS;
  return Math.max(MIN_TTL_SECONDS, Math.min(MAX_TTL_SECONDS, Math.floor(value)));
}

function sanitizeUserId(userId) {
  const text = String(userId || 'anon')
    .trim()
    .replace(/[^A-Za-z0-9._:@-]/g, '_')
    .slice(0, 64);
  return text || 'anon';
}

/**
 * Coturn `use-auth-secret` / TURN REST (RFC 5766 time-limited credentials).
 * username = `${expiryUnix}:${userId}`
 * credential = base64(hmac-sha1(secret, username))
 */
export function mintTurnRestCredential(secret, userId, {
  nowMs = Date.now(),
  ttlSeconds = DEFAULT_TTL_SECONDS,
} = {}) {
  const ttl = clampTtl(ttlSeconds);
  const expiryUnix = Math.floor(nowMs / 1000) + ttl;
  const username = `${expiryUnix}:${sanitizeUserId(userId)}`;
  const credential = crypto
    .createHmac('sha1', String(secret))
    .update(username)
    .digest('base64');
  return {
    username,
    credential,
    ttl,
    expiresAt: new Date(expiryUnix * 1000).toISOString(),
  };
}

function expandTurnUrls(rawUrls) {
  const urls = new Set(rawUrls);
  for (const url of [...urls]) {
    if (url.startsWith('turn:') && !url.includes('transport=')) {
      urls.add(url.includes('?') ? `${url}&transport=udp` : `${url}?transport=udp`);
      urls.add(url.includes('?') ? `${url}&transport=tcp` : `${url}?transport=tcp`);
    } else if (url.startsWith('turn:') && !url.includes('transport=tcp')) {
      urls.add(url.includes('?') ? `${url}&transport=tcp` : `${url}?transport=tcp`);
    }
  }
  return [...urls];
}

/**
 * Prefer explicit WEBRTC_TURNS_URL; otherwise derive turns:443 / turns:5349
 * templates from TURN host when WEBRTC_TURN_TLS_HOST or first turn: host is set.
 */
export function resolveTurnsUrls(env = process.env) {
  const explicit = splitCsv(env.WEBRTC_TURNS_URL);
  if (explicit.length > 0) return explicit;

  const host =
    String(env.WEBRTC_TURN_TLS_HOST || '').trim() ||
    (() => {
      const first = splitCsv(env.WEBRTC_TURN_URL)[0] || '';
      const match = first.match(/^turns?:([^:/?]+)/i);
      return match ? match[1] : '';
    })();
  if (!host) return [];
  if (String(env.WEBRTC_TURN_TLS_ENABLED || '').toLowerCase() !== 'true') {
    return [];
  }
  return [
    `turns:${host}:443?transport=tcp`,
    `turns:${host}:5349?transport=tcp`,
  ];
}

export function buildIceServersFromEnv(env = process.env, { userId } = {}) {
  const iceServers = [];
  const stunRaw = env.WEBRTC_STUN_URLS || DEFAULT_STUN;
  for (const url of splitCsv(stunRaw)) {
    iceServers.push({ urls: url });
  }

  const turnUrls = expandTurnUrls(splitCsv(env.WEBRTC_TURN_URL));
  const turnsUrls = resolveTurnsUrls(env);
  const allTurnUrls = [...new Set([...turnUrls, ...turnsUrls])];

  const hmacSecret = String(env.WEBRTC_TURN_SECRET || '').trim();
  const staticUser = String(env.WEBRTC_TURN_USERNAME || '').trim();
  const staticCred = String(env.WEBRTC_TURN_CREDENTIAL || '').trim();
  const ttlSeconds = clampTtl(env.WEBRTC_TURN_TTL_SECONDS);

  let credentialType = 'none';
  let ttl = null;
  let expiresAt = null;
  let username = null;
  let credential = null;

  if (allTurnUrls.length > 0 && hmacSecret) {
    const minted = mintTurnRestCredential(hmacSecret, userId, { ttlSeconds });
    username = minted.username;
    credential = minted.credential;
    ttl = minted.ttl;
    expiresAt = minted.expiresAt;
    credentialType = 'hmac';
    iceServers.push({
      urls: allTurnUrls,
      username,
      credential,
      credentialType: 'password',
    });
  } else if (allTurnUrls.length > 0 && staticUser && staticCred) {
    username = staticUser;
    credential = staticCred;
    credentialType = 'static';
    iceServers.push({
      urls: allTurnUrls,
      username,
      credential,
      credentialType: 'password',
    });
  }

  return {
    iceServers,
    ttl,
    expiresAt,
    credentialType,
    hasTurn: credentialType !== 'none',
  };
}
