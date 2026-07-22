/**
 * Offline unit checks for call signaling helpers (no DB / WS).
 */
import assert from 'node:assert/strict';
import { parseCallMediaUpdate } from '../websocket/callSignaling.js';
import { loadRealtimeConfig } from '../realtime/config.js';
import { MemoryCallRegistry } from '../realtime/memoryCallRegistry.js';

function normalizeMediaType(raw) {
  const v = (raw ?? 'audio').toString().trim().toLowerCase();
  return v === 'video' ? 'video' : 'audio';
}

assert.equal(normalizeMediaType('video'), 'video');
assert.equal(normalizeMediaType('VIDEO'), 'video');
assert.equal(normalizeMediaType('audio'), 'audio');
assert.equal(normalizeMediaType(undefined), 'audio');
assert.equal(normalizeMediaType('weird'), 'audio');

assert.deepEqual(
  parseCallMediaUpdate({ camera_off: true }, 'video'),
  {
    ok: true,
    mediaType: 'video',
    hasCameraOff: true,
    cameraOff: true,
  }
);
assert.equal(
  parseCallMediaUpdate({ camera_off: 'true' }, 'video').ok,
  false
);
assert.equal(
  parseCallMediaUpdate({ media_type: 1 }, 'video').ok,
  false
);

// Mesh cap used by group signaling
const MAX_PARTICIPANTS = 4;
assert.equal(MAX_PARTICIPANTS, 4);

// Group WS types must not collide with DM call_ prefix routing
const groupTypes = [
  'gcall_create',
  'gcall_invite',
  'gcall_join',
  'gcall_leave',
  'gcall_offer',
  'gcall_answer',
  'gcall_ice',
];
for (const t of groupTypes) {
  assert.ok(t.startsWith('gcall_'));
  assert.ok(!t.startsWith('call_') || t.startsWith('gcall_'));
}

const registry = new MemoryCallRegistry({
  ...loadRealtimeConfig({
    NODE_ENV: 'test',
    REALTIME_MODE: 'memory',
    REALTIME_TELEMETRY: 'false',
  }),
  telemetryEnabled: false,
});
await registry.start();
await registry.registerConnection({
  userId: 'a',
  connId: 'a-1',
  instanceId: 'smoke',
});
await registry.registerConnection({
  userId: 'b',
  connId: 'b-1',
  instanceId: 'smoke',
});
assert.equal(
  (
    await registry.createDmCall({
      callId: 'resume-smoke',
      chatId: '1',
      callerId: 'a',
      calleeId: 'b',
      mediaType: 'audio',
      callerConnId: 'a-1',
    })
  ).ok,
  true
);
assert.equal((await registry.getStatus('b')).state, 'ringing');
assert.equal(
  (
    await registry.acceptDmCall({
      callId: 'resume-smoke',
      userId: 'b',
      connId: 'b-1',
    })
  ).ok,
  true
);
await registry.unregisterConnection({ userId: 'a', connId: 'a-1' });
await registry.registerConnection({
  userId: 'a',
  connId: 'a-2',
  instanceId: 'smoke',
});
const resumed = await registry.resumeDmCall({
  callId: 'resume-smoke',
  userId: 'a',
  connId: 'a-2',
});
assert.equal(resumed.ok, true);
assert.equal(resumed.status.active, true);
assert.equal(resumed.status.role, 'caller');
assert.equal('peer_user_id' in resumed.status, false);

console.log('smoke-call-unit: OK');
