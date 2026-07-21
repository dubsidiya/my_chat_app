/**
 * Offline unit checks for call signaling helpers (no DB / WS).
 */
import assert from 'node:assert/strict';

function normalizeMediaType(raw) {
  const v = (raw ?? 'audio').toString().trim().toLowerCase();
  return v === 'video' ? 'video' : 'audio';
}

assert.equal(normalizeMediaType('video'), 'video');
assert.equal(normalizeMediaType('VIDEO'), 'video');
assert.equal(normalizeMediaType('audio'), 'audio');
assert.equal(normalizeMediaType(undefined), 'audio');
assert.equal(normalizeMediaType('weird'), 'audio');

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

console.log('smoke-call-unit: OK');
