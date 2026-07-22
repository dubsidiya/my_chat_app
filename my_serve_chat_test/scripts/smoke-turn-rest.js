/**
 * Offline TURN REST / relay URL smoke (no coturn process, no secrets required).
 *
 * Validates HMAC minting, TCP/TLS URL expansion, and a relay-only ICE config
 * shape clients can use for NAT matrix checks.
 */
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

import {
  buildIceServersFromEnv,
  mintTurnRestCredential,
} from '../services/calls/turnCredentials.js';

function relayOnlyConfiguration(iceServers) {
  return {
    iceServers,
    iceTransportPolicy: 'relay',
  };
}

const secret = 'smoke-turn-rest-secret-32chars!!';
const minted = mintTurnRestCredential(secret, 'user-7', {
  nowMs: 1_700_000_000_000,
  ttlSeconds: 3600,
});
const expected = crypto
  .createHmac('sha1', secret)
  .update(minted.username)
  .digest('base64');
assert.equal(minted.credential, expected);
assert.match(minted.username, /^\d+:user-7$/);

const payload = buildIceServersFromEnv(
  {
    WEBRTC_STUN_URLS: 'stun:stun.example:3478',
    WEBRTC_TURN_URL: 'turn:turn.example:3478',
    WEBRTC_TURN_SECRET: secret,
    WEBRTC_TURN_TLS_ENABLED: 'true',
    WEBRTC_TURN_TLS_HOST: 'turn.example',
    WEBRTC_TURN_TTL_SECONDS: '7200',
  },
  { userId: 'user-7' }
);

assert.equal(payload.credentialType, 'hmac');
assert.equal(payload.hasTurn, true);
assert.equal(payload.ttl, 7200);
assert.ok(payload.expiresAt);

const turnEntry = payload.iceServers.find((entry) =>
  Array.isArray(entry.urls)
    ? entry.urls.some((url) => String(url).startsWith('turn'))
    : String(entry.urls || '').startsWith('turn')
);
assert.ok(turnEntry, 'expected TURN/TURNS entry');
const urls = turnEntry.urls.map(String);
assert.ok(urls.some((url) => url.includes('transport=tcp')), 'tcp fallback');
assert.ok(
  urls.some((url) => url.startsWith('turns:') && url.includes(':443')),
  'turns:443 template'
);
assert.ok(
  urls.some((url) => url.startsWith('turns:') && url.includes(':5349')),
  'turns:5349 template'
);
assert.equal('authToken' in turnEntry, false);
assert.equal('participantToken' in turnEntry, false);

const relayOnly = relayOnlyConfiguration(payload.iceServers);
assert.equal(relayOnly.iceTransportPolicy, 'relay');
assert.ok(Array.isArray(relayOnly.iceServers));
assert.ok(relayOnly.iceServers.length >= 2);

console.log('smoke-turn-rest: OK (hmac + tcp/tls urls + relay-only shape)');
