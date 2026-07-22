import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';
import { createClient } from 'redis';

import { loadRealtimeConfig } from '../realtime/config.js';
import { RealtimeRuntime } from '../realtime/runtime.js';

const redisUrl = String(process.env.TEST_REDIS_URL || '').trim();
const requireRedis =
  process.env.REQUIRE_REDIS_TESTS === '1' ||
  process.env.CI === 'true' ||
  process.env.CI === '1';

if (requireRedis && !redisUrl) {
  throw new Error(
    'REQUIRE_REDIS_TESTS/CI is set but TEST_REDIS_URL is empty — Redis integration must run'
  );
}

function redisConfig(namespace, instanceId) {
  return {
    ...loadRealtimeConfig({
      NODE_ENV: 'test',
      REALTIME_MODE: 'memory',
      REALTIME_TELEMETRY: 'false',
    }),
    mode: 'redis',
    redisUrl,
    namespace,
    instanceId,
    sweepIntervalMs: 250,
    telemetryEnabled: false,
  };
}

async function waitFor(predicate, timeoutMs = 5_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = predicate();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error('timed out waiting for Redis pub/sub delivery');
}

async function cleanupNamespace(namespace) {
  const client = createClient({
    url: redisUrl,
    socket: { reconnectStrategy: false },
  });
  client.on('error', () => {});
  await client.connect();
  const keys = await client.keys(`rt:{${namespace}}:*`);
  await Promise.all(keys.map((key) => client.del(key)));
  await client.close();
}

test(
  'Redis registry and pub/sub coordinate two runtimes',
  { skip: !redisUrl, timeout: 20_000 },
  async () => {
    const namespace = `test-${crypto.randomUUID().replaceAll('-', '')}`;
    const runtimeA = new RealtimeRuntime(redisConfig(namespace, 'runtime-a'));
    const runtimeB = new RealtimeRuntime(redisConfig(namespace, 'runtime-b'));
    const receivedA = [];
    const receivedB = [];
    runtimeA.setLocalDelivery((envelope) => receivedA.push(envelope));
    runtimeB.setLocalDelivery((envelope) => receivedB.push(envelope));

    try {
      assert.equal(await runtimeA.start(), true);
      assert.equal(await runtimeB.start(), true);
      assert.equal(runtimeA.isReady(), true);
      assert.equal(runtimeB.isReady(), true);

      await runtimeA.registry.registerConnection({
        userId: 'caller',
        connId: 'caller-conn',
        instanceId: runtimeA.instanceId,
      });
      await runtimeB.registry.registerConnection({
        userId: 'callee',
        connId: 'callee-conn',
        instanceId: runtimeB.instanceId,
      });

      const created = await runtimeA.registry.createDmCall({
        callId: 'unsafe/../call:{id}',
        chatId: '9',
        callerId: 'caller',
        calleeId: 'callee',
        mediaType: 'video',
        callerConnId: 'caller-conn',
      });
      assert.equal(created.ok, true);
      assert.equal(
        (
          await runtimeB.registry.createDmCall({
            callId: 'other',
            chatId: '10',
            callerId: 'callee',
            calleeId: 'third',
            mediaType: 'audio',
          })
        ).code,
        'busy'
      );

      await runtimeA.deliver('callee', {
        type: 'call_invite',
        call_id: 'unsafe/../call:{id}',
      });
      const invite = await waitFor(() =>
        receivedB.find(
          (item) =>
            item.userId === 'callee' &&
            item.payload?.type === 'call_invite'
        )
      );
      assert.equal(invite.payload.call_id, 'unsafe/../call:{id}');

      const accepted = await runtimeB.registry.acceptDmCall({
        callId: 'unsafe/../call:{id}',
        userId: 'callee',
        connId: 'callee-conn',
      });
      assert.equal(accepted.ok, true);
      assert.equal(
        (await runtimeA.registry.getCall('unsafe/../call:{id}')).state,
        'accepted'
      );

      await runtimeB.deliver(
        'caller',
        { type: 'call_accept', call_id: 'unsafe/../call:{id}' },
        { connId: 'caller-conn' }
      );
      const acceptDelivery = await waitFor(() =>
        receivedA.find((item) => item.payload?.type === 'call_accept')
      );
      assert.equal(acceptDelivery.connId, 'caller-conn');

      await runtimeB.registry.registerConnection({
        userId: 'callee',
        connId: 'callee-second',
        instanceId: runtimeB.instanceId,
      });
      assert.equal(
        (
          await runtimeB.registry.authorizeMedia({
            callId: 'unsafe/../call:{id}',
            userId: 'callee',
            connId: 'callee-second',
          })
        ).code,
        'media_owned_elsewhere'
      );
      await runtimeB.registry.unregisterConnection({
        userId: 'callee',
        connId: 'callee-conn',
      });
      const resumed = await runtimeB.registry.resumeDmCall({
        callId: 'unsafe/../call:{id}',
        userId: 'callee',
        connId: 'callee-second',
      });
      assert.equal(resumed.ok, true);
      assert.equal(resumed.resumed, true);
      assert.equal(resumed.fence, 2);
      const staleClose = await runtimeB.registry.unregisterConnection({
        userId: 'callee',
        connId: 'callee-conn',
      });
      assert.equal(staleClose.wasMedia, false);

      const status = await runtimeA.registry.getStatus('caller');
      assert.equal(status.active, true);
      assert.equal(status.role, 'caller');
      assert.equal('peer_user_id' in status, false);

      const ended = await runtimeA.registry.terminateDmCall({
        callId: 'unsafe/../call:{id}',
        userId: 'caller',
        connId: 'caller-conn',
        reason: 'hangup',
      });
      assert.equal(ended.ok, true);
      assert.deepEqual(await runtimeB.registry.getStatus('callee'), {
        active: false,
      });

      const groupCreated =
        await runtimeA.registry.createLiveKitGroupCall({
          callId: '00000000-0000-4000-8000-000000000001',
          roomName: 'shared-livekit-room',
          chatId: '77',
          hostId: 'caller',
          mediaType: 'video',
          participants: [
            { userId: 'caller', label: 'Caller' },
            { userId: 'callee', label: 'Callee' },
          ],
          instanceId: runtimeA.instanceId,
        });
      assert.equal(groupCreated.ok, true);
      assert.equal(
        (
          await runtimeB.registry.getLiveKitGroupCall(
            groupCreated.call.callId
          )
        ).roomName,
        'shared-livekit-room'
      );
      const groupJoined =
        await runtimeB.registry.joinLiveKitGroupCall({
          callId: groupCreated.call.callId,
          userId: 'callee',
          connId: 'callee-second',
          answerTokenHash: 'ticket-hash-a',
        });
      assert.equal(groupJoined.ok, true);
      await runtimeA.registry.registerConnection({
        userId: 'callee',
        connId: 'callee-third',
        instanceId: runtimeA.instanceId,
      });
      assert.equal(
        (
          await runtimeA.registry.joinLiveKitGroupCall({
            callId: groupCreated.call.callId,
            userId: 'callee',
            connId: 'callee-third',
            answerTokenHash: 'ticket-hash-b',
          })
        ).code,
        'media_owned_elsewhere'
      );
      assert.equal(
        (
          await runtimeA.registry.acquireChatBusy({
            chatId: '77',
            kind: 'legacy_group_mesh',
            ownerId: 'mesh-call',
            instanceId: runtimeA.instanceId,
          })
        ).code,
        'chat_call_active'
      );
      const groupEnded =
        await runtimeB.registry.finishLiveKitGroupCall({
          callId: groupCreated.call.callId,
          reason: 'test_cleanup',
        });
      assert.equal(groupEnded.ended, true);
      assert.equal(await runtimeA.registry.getBusy('caller'), null);

      for (const [userId, connId, runtime] of [
        ['x', 'x-conn', runtimeA],
        ['y', 'y-conn', runtimeB],
      ]) {
        await runtime.registry.registerConnection({
          userId,
          connId,
          instanceId: runtime.instanceId,
        });
      }
      const inviteRace = await Promise.all([
        runtimeA.registry.createDmCall({
          callId: 'race-x',
          chatId: '11',
          callerId: 'x',
          calleeId: 'y',
          mediaType: 'audio',
          callerConnId: 'x-conn',
        }),
        runtimeB.registry.createDmCall({
          callId: 'race-y',
          chatId: '11',
          callerId: 'y',
          calleeId: 'x',
          mediaType: 'audio',
          callerConnId: 'y-conn',
        }),
      ]);
      assert.equal(inviteRace.filter((result) => result.ok).length, 1);
      assert.equal(
        inviteRace.filter((result) => result.code === 'busy').length,
        1
      );

      const winning = inviteRace.find((result) => result.ok).call;
      const calleeRuntime =
        winning.calleeId === 'x' ? runtimeA : runtimeB;
      const calleePrimary =
        winning.calleeId === 'x' ? 'x-conn' : 'y-conn';
      const calleeSecond = `${winning.calleeId}-second`;
      await calleeRuntime.registry.registerConnection({
        userId: winning.calleeId,
        connId: calleeSecond,
        instanceId: calleeRuntime.instanceId,
      });
      const acceptRace = await Promise.all([
        calleeRuntime.registry.acceptDmCall({
          callId: winning.callId,
          userId: winning.calleeId,
          connId: calleePrimary,
        }),
        calleeRuntime.registry.acceptDmCall({
          callId: winning.callId,
          userId: winning.calleeId,
          connId: calleeSecond,
        }),
      ]);
      assert.equal(acceptRace.filter((result) => result.ok).length, 1);
      assert.equal(
        acceptRace.filter(
          (result) => result.code === 'media_owned_elsewhere'
        ).length,
        1
      );
      await runtimeA.registry.terminateDmCall({
        callId: winning.callId,
        userId: winning.callerId,
        connId: winning.callerId === 'x' ? 'x-conn' : 'y-conn',
        reason: 'test_cleanup',
      });
    } finally {
      await Promise.allSettled([runtimeA.stop(), runtimeB.stop()]);
      await cleanupNamespace(namespace);
    }
  }
);
