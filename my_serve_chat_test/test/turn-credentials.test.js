import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';

import {
  buildIceServersFromEnv,
  mintTurnRestCredential,
  resolveTurnsUrls,
} from '../services/calls/turnCredentials.js';

test('mintTurnRestCredential matches coturn use-auth-secret HMAC', () => {
  const secret = 'unit-test-turn-secret';
  const minted = mintTurnRestCredential(secret, 'user-42', {
    nowMs: 1_700_000_000_000,
    ttlSeconds: 3600,
  });
  assert.equal(minted.username, '1700003600:user-42');
  const expected = crypto
    .createHmac('sha1', secret)
    .update(minted.username)
    .digest('base64');
  assert.equal(minted.credential, expected);
  assert.equal(minted.ttl, 3600);
  assert.equal(minted.expiresAt, '2023-11-14T23:13:20.000Z');
});

test('buildIceServersFromEnv prefers HMAC over static shared credentials', () => {
  const result = buildIceServersFromEnv(
    {
      WEBRTC_STUN_URLS: 'stun:example:3478',
      WEBRTC_TURN_URL: 'turn:turn.example:3478',
      WEBRTC_TURN_SECRET: 'hmac-secret',
      WEBRTC_TURN_USERNAME: 'legacy-user',
      WEBRTC_TURN_CREDENTIAL: 'legacy-pass',
      WEBRTC_TURN_TTL_SECONDS: '7200',
    },
    { userId: '7' }
  );
  assert.equal(result.credentialType, 'hmac');
  assert.equal(result.hasTurn, true);
  assert.equal(result.ttl, 7200);
  assert.match(result.expiresAt, /^\d{4}-/);
  const turn = result.iceServers.find((entry) =>
    Array.isArray(entry.urls)
      ? entry.urls.some((url) => String(url).startsWith('turn:'))
      : String(entry.urls || '').startsWith('turn:')
  );
  assert.ok(turn);
  assert.match(turn.username, /^\d+:7$/);
  assert.ok(turn.urls.includes('turn:turn.example:3478?transport=tcp'));
});

test('buildIceServersFromEnv keeps static credentials when HMAC secret absent', () => {
  const result = buildIceServersFromEnv({
    WEBRTC_TURN_URL: 'turn:turn.example:3478?transport=udp',
    WEBRTC_TURN_USERNAME: 'reollity',
    WEBRTC_TURN_CREDENTIAL: 'shared-secret',
  });
  assert.equal(result.credentialType, 'static');
  assert.equal(result.ttl, null);
  assert.equal(result.iceServers.at(-1).username, 'reollity');
});

test('resolveTurnsUrls uses explicit list or TLS host templates', () => {
  assert.deepEqual(
    resolveTurnsUrls({ WEBRTC_TURNS_URL: 'turns:a:443?transport=tcp' }),
    ['turns:a:443?transport=tcp']
  );
  assert.deepEqual(
    resolveTurnsUrls({
      WEBRTC_TURN_URL: 'turn:turn.example:3478',
      WEBRTC_TURN_TLS_ENABLED: 'true',
    }),
    [
      'turns:turn.example:443?transport=tcp',
      'turns:turn.example:5349?transport=tcp',
    ]
  );
  assert.deepEqual(
    resolveTurnsUrls({
      WEBRTC_TURN_URL: 'turn:turn.example:3478',
      WEBRTC_TURN_TLS_ENABLED: 'false',
    }),
    []
  );
});
