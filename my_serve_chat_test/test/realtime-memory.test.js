import assert from 'node:assert/strict';
import test from 'node:test';

import { loadRealtimeConfig } from '../realtime/config.js';
import { MemoryCallRegistry } from '../realtime/memoryCallRegistry.js';
import { RedisCallRegistry } from '../realtime/redisCallRegistry.js';
import { RealtimeRuntime } from '../realtime/runtime.js';

function testConfig(overrides = {}) {
  return {
    ...loadRealtimeConfig({
      NODE_ENV: 'test',
      REALTIME_MODE: 'memory',
      REALTIME_TELEMETRY: 'false',
    }),
    ringingTtlMs: 1_000,
    acceptedTtlMs: 10_000,
    tombstoneTtlMs: 2_000,
    connectionLeaseMs: 1_000,
    disconnectGraceMs: 500,
    ringingDisconnectGraceMs: 100,
    busyLeaseMs: 2_000,
    sweepIntervalMs: 250,
    telemetryEnabled: false,
    ...overrides,
  };
}

test('production config requires explicit Redis control plane', () => {
  assert.throws(
    () =>
      loadRealtimeConfig({
        NODE_ENV: 'production',
        REALTIME_MODE: 'memory',
      }),
    /REALTIME_MODE=redis/
  );
  assert.throws(
    () =>
      loadRealtimeConfig({
        NODE_ENV: 'production',
        REALTIME_MODE: 'redis',
      }),
    /REDIS_URL/
  );
  assert.equal(
    loadRealtimeConfig({
      NODE_ENV: 'development',
      REDIS_URL: 'redis://127.0.0.1:6379',
    }).mode,
    'redis'
  );
  assert.throws(
    () =>
      loadRealtimeConfig({
        NODE_ENV: 'test',
        REALTIME_MODE: 'memory',
        WS_HEARTBEAT_MS: '10000',
        WS_CONNECTION_LEASE_MS: '15000',
      }),
    /two heartbeat intervals/
  );
  assert.throws(
    () =>
      loadRealtimeConfig({
        NODE_ENV: 'test',
        REALTIME_MODE: 'memory',
        CALL_RINGING_TTL_MS: '75000',
        CALL_RINGING_DISCONNECT_GRACE_MS: '3000',
        CALL_BUSY_LEASE_MS: '60000',
      }),
    /cover ringing TTL/
  );
  const redisRegistry = new RedisCallRegistry(
    { ...testConfig(), namespace: 'hash-test' },
    { isReady: false }
  );
  assert.equal(
    redisRegistry._callKey('../unsafe:{call}').includes('../unsafe:{call}'),
    false
  );
});

test('memory registry enforces busy, media fencing, status and tombstones', async () => {
  let now = 1_000;
  const registry = new MemoryCallRegistry(testConfig(), {
    now: () => now,
  });
  await registry.start();
  await registry.registerConnection({
    userId: 'caller',
    connId: 'caller-media',
    instanceId: 'one',
  });
  await registry.registerConnection({
    userId: 'callee',
    connId: 'callee-media',
    instanceId: 'one',
  });

  const created = await registry.createDmCall({
    callId: '../unsafe/call:id',
    chatId: '7',
    callerId: 'caller',
    calleeId: 'callee',
    mediaType: 'video',
    callerConnId: 'caller-media',
  });
  assert.equal(created.ok, true);
  assert.match(created.call.callKitUuid, /^[0-9a-f-]{36}$/);
  assert.equal(
    (
      await registry.createDmCall({
        callId: 'second',
        chatId: '8',
        callerId: 'caller',
        calleeId: 'other',
        mediaType: 'audio',
        callerConnId: 'caller-media',
      })
    ).code,
    'busy'
  );

  const accepted = await registry.acceptDmCall({
    callId: '../unsafe/call:id',
    userId: 'callee',
    connId: 'callee-media',
  });
  assert.equal(accepted.ok, true);
  assert.equal(accepted.call.state, 'accepted');

  await registry.registerConnection({
    userId: 'callee',
    connId: 'callee-other-tab',
    instanceId: 'one',
  });
  const stolen = await registry.authorizeMedia({
    callId: '../unsafe/call:id',
    userId: 'callee',
    connId: 'callee-other-tab',
  });
  assert.equal(stolen.code, 'media_owned_elsewhere');

  const status = await registry.getStatus('callee');
  assert.deepEqual(
    Object.keys(status).sort(),
    [
      'active',
      'call_id',
      'callkit_uuid',
      'chat_id',
      'created_at',
      'expires_at',
      'media_type',
      'revision',
      'role',
      'state',
      'updated_at',
    ].sort()
  );
  assert.equal(status.role, 'callee');
  assert.equal('peer_user_id' in status, false);
  assert.equal('media' in status, false);

  await registry.unregisterConnection({
    userId: 'callee',
    connId: 'callee-media',
  });
  const resumed = await registry.resumeDmCall({
    callId: '../unsafe/call:id',
    userId: 'callee',
    connId: 'callee-other-tab',
  });
  assert.equal(resumed.ok, true);
  assert.equal(resumed.resumed, true);
  assert.equal(resumed.fence, 2);

  const nonMediaHangup = await registry.terminateDmCall({
    callId: '../unsafe/call:id',
    userId: 'caller',
    connId: 'caller-chat-tab',
  });
  assert.equal(nonMediaHangup.code, 'media_owned_elsewhere');

  const ended = await registry.terminateDmCall({
    callId: '../unsafe/call:id',
    userId: 'caller',
    connId: 'caller-media',
    reason: 'hangup',
  });
  assert.equal(ended.ok, true);
  assert.equal(await registry.getBusy('caller'), null);
  assert.equal(
    (
      await registry.createDmCall({
        callId: '../unsafe/call:id',
        chatId: '7',
        callerId: 'caller',
        calleeId: 'callee',
        mediaType: 'audio',
        callerConnId: 'caller-media',
      })
    ).code,
    'call_id_exists'
  );

  now += 2_001;
  await registry.sweepExpired();
  await registry.registerConnection({
    userId: 'caller',
    connId: 'caller-new',
    instanceId: 'one',
  });
  assert.equal(
    (
      await registry.createDmCall({
        callId: '../unsafe/call:id',
        chatId: '7',
        callerId: 'caller',
        calleeId: 'callee',
        mediaType: 'audio',
        callerConnId: 'caller-new',
      })
    ).ok,
    true
  );
});

test('memory registry expires ringing and only releases exact media leg', async () => {
  let now = 10_000;
  const registry = new MemoryCallRegistry(testConfig(), {
    now: () => now,
  });
  await registry.start();
  for (const connId of ['media', 'chat']) {
    await registry.registerConnection({
      userId: 'a',
      connId,
      instanceId: 'one',
    });
  }
  await registry.registerConnection({
    userId: 'b',
    connId: 'b-media',
    instanceId: 'one',
  });
  await registry.createDmCall({
    callId: 'disconnect-test',
    chatId: '1',
    callerId: 'a',
    calleeId: 'b',
    mediaType: 'audio',
    callerConnId: 'media',
  });
  await registry.acceptDmCall({
    callId: 'disconnect-test',
    userId: 'b',
    connId: 'b-media',
  });

  const chatClosed = await registry.unregisterConnection({
    userId: 'a',
    connId: 'chat',
  });
  assert.equal(chatClosed.wasMedia, false);
  now += 600;
  assert.equal((await registry.sweepExpired()).length, 0);

  const mediaClosed = await registry.unregisterConnection({
    userId: 'a',
    connId: 'media',
  });
  assert.equal(mediaClosed.wasMedia, true);
  now += 499;
  assert.equal((await registry.sweepExpired()).length, 0);
  now += 2;
  const ended = await registry.sweepExpired();
  assert.equal(ended.length, 1);
  assert.equal(ended[0].reason, 'disconnected');

  await registry.registerConnection({
    userId: 'a',
    connId: 'ring-media',
    instanceId: 'one',
  });
  await registry.createDmCall({
    callId: 'ring-expiry',
    chatId: '1',
    callerId: 'a',
    calleeId: 'b',
    mediaType: 'audio',
    callerConnId: 'ring-media',
  });
  now += 1_001;
  const expired = await registry.sweepExpired();
  assert.equal(expired[0].reason, 'ringing_timeout');
});

test('legacy group busy bridge blocks DM creation', async () => {
  const registry = new MemoryCallRegistry(testConfig());
  await registry.start();
  await registry.registerConnection({
    userId: 'group-user',
    connId: 'group-user-conn',
    instanceId: 'one',
  });
  assert.equal(
    (
      await registry.acquireBusy({
        userId: 'group-user',
        kind: 'legacy_group_mesh',
        ownerId: 'group-call',
        instanceId: 'one',
      })
    ).ok,
    true
  );
  const blocked = await registry.createDmCall({
    callId: 'dm-call',
    chatId: '2',
    callerId: 'group-user',
    calleeId: 'peer',
    mediaType: 'audio',
    callerConnId: 'group-user-conn',
  });
  assert.equal(blocked.code, 'busy');
  await registry.releaseBusy({
    userId: 'group-user',
    kind: 'legacy_group_mesh',
    ownerId: 'group-call',
  });
  assert.equal(
    (
      await registry.createDmCall({
        callId: 'dm-call',
        chatId: '2',
        callerId: 'group-user',
        calleeId: 'peer',
        mediaType: 'audio',
        callerConnId: 'group-user-conn',
      })
    ).ok,
    true
  );
});

test('memory registry owns LiveKit group roster, chat lock and tombstone', async () => {
  let now = 5_000;
  const registry = new MemoryCallRegistry(testConfig(), {
    now: () => now,
  });
  await registry.start();
  await registry.registerConnection({
    userId: '2',
    connId: 'guest-device-a',
    instanceId: 'one',
  });
  await registry.registerConnection({
    userId: '2',
    connId: 'guest-device-b',
    instanceId: 'one',
  });
  const created = await registry.createLiveKitGroupCall({
    callId: '00000000-0000-4000-8000-000000000001',
    roomName: 'room-one',
    chatId: '9',
    hostId: '1',
    mediaType: 'video',
    participants: [
      { userId: '1', label: 'Host' },
      { userId: '2', label: 'Guest' },
    ],
    instanceId: 'one',
  });
  assert.equal(created.ok, true);
  assert.equal(
    (
      await registry.acquireChatBusy({
        chatId: '9',
        kind: 'legacy_group_mesh',
        ownerId: 'mesh',
      })
    ).code,
    'chat_call_active'
  );
  const joined = await registry.joinLiveKitGroupCall({
    callId: created.call.callId,
    userId: '2',
    connId: 'guest-device-a',
    answerTokenHash: 'answer-hash-a',
  });
  assert.equal(joined.call.participants['2'].state, 'joined');
  const groupStatus = await registry.getStatus('2');
  assert.equal(groupStatus.transport, 'livekit');
  assert.equal(groupStatus.participant_state, 'joined');
  assert.match(groupStatus.callkit_uuid, /^[0-9a-f-]{36}$/);
  assert.equal(
    (
      await registry.joinLiveKitGroupCall({
        callId: created.call.callId,
        userId: '2',
        connId: 'guest-device-b',
        answerTokenHash: 'answer-hash-b',
      })
    ).code,
    'media_owned_elsewhere'
  );
  const guestDisconnected = await registry.leaveLiveKitGroupCall({
    callId: created.call.callId,
    userId: '2',
    webhook: true,
  });
  assert.equal(guestDisconnected.reconnectGrace, true);
  const guestRejoined = await registry.joinLiveKitGroupCall({
    callId: created.call.callId,
    userId: '2',
  });
  assert.equal(guestRejoined.call.participants['2'].state, 'joined');

  const hostDisconnected = await registry.leaveLiveKitGroupCall({
    callId: created.call.callId,
    userId: '1',
    webhook: true,
  });
  assert.equal(hostDisconnected.hostGrace, true);
  now += testConfig().disconnectGraceMs + 1;
  const ended = await registry.sweepExpired();
  assert.equal(ended[0].reason, 'host_disconnected');
  assert.equal(await registry.getChatBusy('9'), null);
  assert.equal(
    (
      await registry.getLiveKitGroupCallTombstone(created.call.callId)
    ).kind,
    'livekit_group'
  );
});

test('memory runtime honors targeted and excluded local delivery', async () => {
  const runtime = new RealtimeRuntime(testConfig());
  const received = [];
  runtime.setLocalDelivery((envelope) => received.push(envelope));
  await runtime.start();
  await runtime.deliver(
    'user',
    { type: 'call_accept' },
    { connId: 'media', excludeConnId: 'other' }
  );
  assert.equal(received.length, 1);
  assert.equal(received[0].connId, 'media');
  assert.equal(received[0].excludeConnId, 'other');
  await runtime.stop();
});
