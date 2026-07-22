import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';

import {
  createIssueLiveKitGroupTokenHandler,
  createLiveKitWebhookHandler,
} from '../controllers/livekitGroupCallsController.js';
import { loadRealtimeConfig } from '../realtime/config.js';
import { RealtimeRuntime } from '../realtime/runtime.js';
import {
  createLiveKitGroupCallCoordinator,
} from '../services/calls/livekitGroupCallCoordinator.js';
import {
  loadLiveKitGroupConfig,
  selectGroupTransport,
} from '../services/calls/livekitGroupConfig.js';
import { FakeLiveKitRoomProvider } from '../services/calls/livekitProvider.js';
import { sendLiveKitGroupCallPushToUser } from '../utils/pushNotifications.js';
import { handleLiveKitGroupCallSignaling } from '../websocket/livekitGroupCallSignaling.js';

function realtimeConfig() {
  return {
    ...loadRealtimeConfig({
      NODE_ENV: 'test',
      REALTIME_MODE: 'memory',
      REALTIME_TELEMETRY: 'false',
    }),
    ringingTtlMs: 10_000,
    acceptedTtlMs: 60_000,
    busyLeaseMs: 60_000,
    telemetryEnabled: false,
  };
}

function liveKitConfig(overrides = {}) {
  return {
    ...loadLiveKitGroupConfig({
      NODE_ENV: 'test',
      LIVEKIT_GROUP_PROVIDER: 'fake',
      LIVEKIT_GROUP_FEATURE_ENABLED: 'true',
      GROUP_CALL_DEFAULT_TRANSPORT: 'livekit',
      LIVEKIT_GROUP_MAX_PARTICIPANTS: '4',
      LIVEKIT_WEBHOOK_ENABLED: 'true',
    }),
    ...overrides,
  };
}

function fakeDatabase() {
  return {
    memberAllowed: true,
    async query(sql, params) {
      if (/SELECT c\.id AS chat_id/.test(sql)) {
        return {
          rows: [
            {
              chat_id: 9,
              is_group: true,
              chat_name: 'Team',
              user_id: 1,
              label: 'Host',
            },
            {
              chat_id: 9,
              is_group: true,
              chat_name: 'Team',
              user_id: 2,
              label: 'Guest',
            },
          ],
        };
      }
      if (/SELECT c\.is_group/.test(sql)) {
        return {
          rows: this.memberAllowed ? [{ is_group: true }] : [],
        };
      }
      if (/SELECT COALESCE\(NULLIF\(TRIM\(display_name\)/.test(sql)) {
        return { rows: [{ label: `User ${params[0]}` }] };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };
}

function fakeResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: null,
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    status(value) {
      this.statusCode = value;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    },
  };
}

async function withCoordinator(callback, { failCreate = false } = {}) {
  const runtime = new RealtimeRuntime(realtimeConfig());
  await runtime.start();
  const config = liveKitConfig();
  const provider = new FakeLiveKitRoomProvider(config);
  provider.failCreate = failCreate;
  const database = fakeDatabase();
  const pushes = [];
  const coordinator = createLiveKitGroupCallCoordinator({
    config,
    provider,
    pool: database,
    runtime,
    pushSender: async (_pool, userId, payload) => {
      pushes.push({ userId, payload });
      return { successCount: 1 };
    },
  });
  try {
    return await callback({
      coordinator,
      runtime,
      provider,
      database,
      pushes,
    });
  } finally {
    await runtime.stop();
  }
}

test('feature-off defaults to mesh and needs no LiveKit credentials', () => {
  const config = loadLiveKitGroupConfig({
    NODE_ENV: 'test',
    GROUP_CALL_DEFAULT_TRANSPORT: 'mesh',
    GROUP_CALL_LIVEKIT_ROLLOUT_PERCENT: '0',
  });
  assert.equal(config.enabled, false);
  assert.equal(
    selectGroupTransport(
      { chatId: '9', protocolVersion: 2, appVersion: '1.0.0' },
      config
    ),
    'mesh'
  );
});

test('rollout selection is deterministic and excludes old protocols', () => {
  const config = liveKitConfig({
    defaultTransport: 'mesh',
    rolloutPercent: 37,
  });
  const first = selectGroupTransport(
    { chatId: '912', protocolVersion: 2, appVersion: '1.0.0' },
    config
  );
  const second = selectGroupTransport(
    { chatId: '912', protocolVersion: 2, appVersion: '1.0.0' },
    config
  );
  assert.equal(first, second);
  assert.equal(
    selectGroupTransport(
      { chatId: '912', protocolVersion: 1, appVersion: '0.9.0' },
      config
    ),
    'mesh'
  );
});

test('known old app installations keep group calls on mesh', async () => {
  const config = liveKitConfig();
  const coordinator = createLiveKitGroupCallCoordinator({
    config,
    provider: new FakeLiveKitRoomProvider(config),
    runtime: {},
    pool: {
      async query(sql) {
        assert.match(sql, /FROM push_devices/);
        return {
          rows: [
            {
              user_id: 2,
              capabilities: { livekitGroupProtocolVersion: 1 },
              app_version: '0.9.0',
            },
          ],
        };
      },
    },
  });
  assert.equal(
    await coordinator.hasKnownUnsupportedLiveKitClients(['1', '2']),
    true
  );
});

test('feature-off lkcall_create selects mesh before session creation', async () => {
  const runtime = new RealtimeRuntime(realtimeConfig());
  const delivered = [];
  runtime.setLocalDelivery((envelope) => delivered.push(envelope));
  await runtime.start();
  const config = loadLiveKitGroupConfig({
    NODE_ENV: 'test',
    GROUP_CALL_DEFAULT_TRANSPORT: 'mesh',
    GROUP_CALL_LIVEKIT_ROLLOUT_PERCENT: '0',
  });
  const coordinator = createLiveKitGroupCallCoordinator({
    config,
    provider: null,
    pool: fakeDatabase(),
    runtime,
  });
  try {
    const handled = await handleLiveKitGroupCallSignaling(
      {
        type: 'lkcall_create',
        chat_id: '9',
        protocol_version: 2,
        initial_media_type: 'video',
      },
      {
        userId: '1',
        userEmail: 'Host',
        runtime,
        coordinator,
        callLimiter: { allow: () => true },
      }
    );
    assert.equal(handled, true);
    assert.equal(delivered[0].payload.type, 'lkcall_use_mesh');
    assert.equal(
      await runtime.registry.getLiveKitGroupCallForChat('9'),
      null
    );
  } finally {
    await runtime.stop();
  }
});

test('server creates scoped LiveKit room and token grants', async () => {
  await withCoordinator(async ({ coordinator, provider }) => {
    const created = await coordinator.createCall({
      chatId: '9',
      hostId: '1',
      hostLabel: 'Host',
      requestedMediaType: 'video',
    });
    assert.equal(created.ok, true);
    assert.match(
      created.call.callId,
      /^[0-9a-f]{8}-[0-9a-f-]{27}$/i
    );
    assert.match(created.call.roomName, /^reollity-local-g-[a-z0-9]+$/);
    assert.equal(provider.createdRooms[0].maxParticipants, 4);

    const handler = createIssueLiveKitGroupTokenHandler({ coordinator });
    const response = fakeResponse();
    await handler(
      {
        params: { callId: created.call.callId },
        userId: '1',
        body: {
          room_name: 'attacker-room',
          identity: 'admin',
          grants: { roomAdmin: true },
        },
      },
      response,
      (error) => {
        throw error;
      }
    );
    assert.equal(response.statusCode, 200);
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.equal(response.body.room_name, created.call.roomName);
    assert.match(response.body.participant_token, /^fake-livekit-token\./);
    const issued = provider.issuedTokens[0];
    assert.equal(issued.userId, '1');
    assert.equal(issued.roomName, created.call.roomName);
    assert.deepEqual(issued.grants.canPublishSources, [
      'camera',
      'microphone',
    ]);
    assert.equal(issued.grants.canPublishData, false);
    assert.equal('roomAdmin' in issued.grants, false);
    assert.equal('roomRecord' in issued.grants, false);

    const answerTicket = 'answer-ticket-for-the-winning-device-123456';
    const joined = await coordinator.joinCall({
      callId: created.call.callId,
      userId: '2',
      answerTokenHash: crypto
        .createHash('sha256')
        .update(answerTicket)
        .digest('base64url'),
    });
    assert.equal(joined.ok, true);
    const losingDeviceResponse = fakeResponse();
    await handler(
      {
        params: { callId: created.call.callId },
        userId: '2',
        body: { answer_ticket: 'wrong-device-ticket-that-is-long-enough' },
      },
      losingDeviceResponse,
      (error) => {
        throw error;
      }
    );
    assert.equal(losingDeviceResponse.statusCode, 403);
    assert.equal(losingDeviceResponse.body.error, 'answered_elsewhere');

    const guestResponse = fakeResponse();
    await handler(
      {
        params: { callId: created.call.callId },
        userId: '2',
        body: {
          grants: { roomAdmin: true },
          answer_ticket: answerTicket,
        },
      },
      guestResponse,
      (error) => {
        throw error;
      }
    );
    assert.equal(guestResponse.statusCode, 200);
    assert.deepEqual(provider.issuedTokens[1].grants, issued.grants);

    await coordinator.finishCall(created.call, 'test_ended');
    const endedResponse = fakeResponse();
    await handler(
      {
        params: { callId: created.call.callId },
        userId: '1',
        body: {},
      },
      endedResponse,
      (error) => {
        throw error;
      }
    );
    assert.equal(endedResponse.statusCode, 410);
  });
});

test('token rejects non-member and feature-off provider', async () => {
  await withCoordinator(async ({ coordinator, database }) => {
    const created = await coordinator.createCall({
      chatId: '9',
      hostId: '1',
      requestedMediaType: 'audio',
    });
    database.memberAllowed = false;
    const response = fakeResponse();
    await createIssueLiveKitGroupTokenHandler({ coordinator })(
      { params: { callId: created.call.callId }, userId: '1', body: {} },
      response,
      (error) => {
        throw error;
      }
    );
    assert.equal(response.statusCode, 403);
    assert.equal(response.body.error, 'not_a_member');
  });

  const response = fakeResponse();
  await createIssueLiveKitGroupTokenHandler({
    coordinator: {
      config: { enabled: false },
      provider: null,
    },
  })(
    {
      params: { callId: '00000000-0000-4000-8000-000000000000' },
      userId: '1',
    },
    response,
    () => {}
  );
  assert.equal(response.statusCode, 503);
});

test('room create failure rolls back registry and sends no push', async () => {
  await withCoordinator(
    async ({ coordinator, runtime, pushes }) => {
      const created = await coordinator.createCall({
        chatId: '9',
        hostId: '1',
        requestedMediaType: 'audio',
      });
      assert.equal(created.code, 'room_create_failed');
      assert.equal(
        await runtime.registry.getLiveKitGroupCallForChat('9'),
        null
      );
      assert.equal(pushes.length, 0);
    },
    { failCreate: true }
  );
});

test('LiveKit busy locks block raw DM and host leave deletes room', async () => {
  await withCoordinator(async ({ coordinator, runtime, provider }) => {
    await runtime.registry.registerConnection({
      userId: '1',
      connId: 'dm-media',
      instanceId: 'test',
    });
    const created = await coordinator.createCall({
      chatId: '9',
      hostId: '1',
      requestedMediaType: 'audio',
    });
    const dm = await runtime.registry.createDmCall({
      callId: 'dm-call',
      chatId: '4',
      callerId: '1',
      calleeId: '3',
      mediaType: 'audio',
      callerConnId: 'dm-media',
    });
    assert.equal(dm.code, 'busy');
    const left = await coordinator.leaveCall({
      callId: created.call.callId,
      userId: '1',
    });
    assert.equal(left.ended, true);
    assert.deepEqual(provider.deletedRooms, [created.call.roomName]);
  });
});

test('duplicate webhook event reconciles participant once', async () => {
  await withCoordinator(async ({ coordinator, runtime }) => {
    const created = await coordinator.createCall({
      chatId: '9',
      hostId: '1',
      requestedMediaType: 'audio',
    });
    const event = {
      id: 'event-1',
      event: 'participant_joined',
      room: { name: created.call.roomName },
      participant: { identity: 'u-2' },
    };
    const first = await coordinator.handleWebhook(event);
    const afterFirst = await runtime.registry.getLiveKitGroupCall(
      created.call.callId
    );
    const second = await coordinator.handleWebhook(event);
    const afterSecond = await runtime.registry.getLiveKitGroupCall(
      created.call.callId
    );
    assert.equal(first.ok, true);
    assert.equal(second.duplicate, true);
    assert.equal(afterFirst.participants['2'].state, 'joined');
    assert.equal(afterSecond.revision, afterFirst.revision);
  });
});

test('webhook requires verified raw application/webhook+json body', async () => {
  await withCoordinator(async ({ coordinator }) => {
    const handler = createLiveKitWebhookHandler({ coordinator });
    const invalid = fakeResponse();
    await handler(
      {
        body: Buffer.from('{}'),
        headers: { authorization: 'Bearer wrong' },
        is: (type) => type === 'application/webhook+json',
      },
      invalid
    );
    assert.equal(invalid.statusCode, 401);

    const valid = fakeResponse();
    await handler(
      {
        body: Buffer.from(
          JSON.stringify({
            id: 'unknown-room-event',
            event: 'room_finished',
            room: { name: 'unknown-room' },
          })
        ),
        headers: { authorization: 'Bearer fake-livekit' },
        is: (type) => type === 'application/webhook+json',
      },
      valid
    );
    assert.equal(valid.statusCode, 200);
    assert.equal(valid.body.ignored, true);
  });
});

test('LiveKit group push contains protocol metadata and no credentials', async () => {
  const captured = [];
  const pushPool = {
    async query(sql) {
      if (/SELECT user_id, installation_id, apns_voip_token/.test(sql)) {
        return { rows: [] };
      }
      if (/SELECT pd\.user_id/.test(sql)) {
        return {
          rows: [
            {
              user_id: 2,
              fcm_token: 'device-token',
              source: 'device',
              capabilities: { livekitGroupProtocolVersion: 2 },
            },
          ],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };
  const provider = {
    async sendMulticast(message) {
      captured.push(message);
      return {
        responses: [{ success: true }],
        successCount: 1,
        failureCount: 0,
      };
    },
  };
  await sendLiveKitGroupCallPushToUser(
    pushPool,
    2,
    {
      callId: 'group-call',
      chatId: '9',
      chatName: 'Team',
      fromUserId: '1',
      fromLabel: 'Host',
      mediaType: 'video',
      expiresAt: Date.now() + 30_000,
      participantToken: 'must-not-leak',
      roomName: 'must-not-leak',
    },
    { provider }
  );
  const data = captured[0].data;
  assert.equal(data.type, 'incoming_livekit_group_call');
  assert.equal(data.provider, 'livekit');
  assert.equal(data.protocolVersion, '2');
  assert.equal(data.initialMediaType, 'video');
  assert.equal('participantToken' in data, false);
  assert.equal('token' in data, false);
  assert.equal('roomName' in data, false);
  assert.equal('room_name' in data, false);
});

test('app auth middleware rejects token endpoint without JWT', async () => {
  process.env.JWT_SECRET = 'test-secret-that-is-long-enough-for-unit-tests';
  const { authenticateToken } = await import(
    `../middleware/auth.js?livekit-auth=${Date.now()}`
  );
  const response = fakeResponse();
  await authenticateToken(
    { headers: {}, method: 'POST', path: '/calls/group/id/token' },
    response,
    () => {
      throw new Error('middleware should not continue');
    }
  );
  assert.equal(response.statusCode, 401);
});
