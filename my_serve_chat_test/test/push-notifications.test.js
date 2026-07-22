import assert from 'node:assert/strict';
import test from 'node:test';

import {
  callNotificationTag,
  sendCallReconciliationPushToUser,
  sendIncomingCallPushToUser,
  sendPushToTokens,
  sendPushToUsers,
} from '../utils/pushNotifications.js';

function fakePool(rows) {
  const updates = [];
  return {
    updates,
    async query(sql, params) {
      if (/SELECT user_id, installation_id, apns_voip_token/.test(sql)) {
        return {
          rows: rows.filter(
            (row) =>
              row.apns_voip_token &&
              row.capabilities?.voipPush === true
          ),
        };
      }
      if (/SELECT pd\.user_id/.test(sql)) {
        return { rows };
      }
      if (/^UPDATE push_devices/.test(sql.trim()) ||
          /^UPDATE users SET fcm_token = NULL/.test(sql.trim())) {
        updates.push({ sql, params });
        return { rows: [], rowCount: 1 };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };
}

function fakeProvider(responses, capture) {
  return {
    async sendMulticast(message) {
      capture.push(message);
      return {
        responses,
        successCount: responses.filter((response) => response.success).length,
        failureCount: responses.filter((response) => !response.success).length,
      };
    },
  };
}

test('fanout dedupes device/legacy tokens and prunes only definitive failures', async () => {
  const pool = fakePool([
    { user_id: 1, fcm_token: 'device-a', source: 'device' },
    { user_id: 1, fcm_token: 'device-a', source: 'legacy' },
    { user_id: 1, fcm_token: 'legacy-b', source: 'legacy' },
    { user_id: 2, fcm_token: 'invalid-c', source: 'device' },
    { user_id: 2, fcm_token: 'transient-d', source: 'device' },
  ]);
  const messages = [];
  const provider = fakeProvider(
    [
      { success: true },
      { success: true },
      {
        success: false,
        error: { code: 'messaging/registration-token-not-registered' },
      },
      {
        success: false,
        error: { code: 'messaging/server-unavailable' },
      },
    ],
    messages
  );

  const result = await sendPushToUsers(
    pool,
    [1, 2],
    'Title',
    'Body',
    { chatId: '9' },
    { provider }
  );

  assert.equal(result.targetCount, 4);
  assert.deepEqual(messages[0].tokens, [
    'device-a',
    'legacy-b',
    'invalid-c',
    'transient-d',
  ]);
  assert.deepEqual(result.definitiveInvalidTokens, ['invalid-c']);
  assert.equal(pool.updates.length, 2);
  assert.deepEqual(pool.updates[0].params, [['invalid-c']]);
  assert.deepEqual(pool.updates[1].params, [['invalid-c']]);
  assert.equal(
    pool.updates.some((entry) =>
      JSON.stringify(entry.params).includes('transient-d')
    ),
    false
  );
});

test('incoming call fanout aligns Android and APNs expiry with ringing state', async () => {
  const pool = fakePool([
    { user_id: 7, fcm_token: 'device-a', source: 'device' },
    { user_id: 7, fcm_token: 'legacy-a', source: 'legacy' },
  ]);
  const messages = [];
  const provider = fakeProvider(
    [{ success: true }, { success: true }],
    messages
  );
  const expiresAt = Date.now() + 30_000;

  const result = await sendIncomingCallPushToUser(
    pool,
    7,
    {
      callId: 'call-123',
      chatId: '8',
      chatName: 'DM',
      fromUserId: '6',
      fromEmail: 'Caller',
      mediaType: 'video',
      expiresAt,
    },
    { provider }
  );

  assert.equal(result.targetCount, 2);
  const message = messages[0];
  assert.equal(message.data.type, 'incoming_call');
  assert.equal(message.data.callId, 'call-123');
  assert.match(message.data.callKitUuid, /^[0-9a-f-]{36}$/);
  assert.equal(message.data.mediaType, 'video');
  assert.equal(message.data.notificationId, '0');
  assert.equal(message.android.notification.tag, callNotificationTag('call-123'));
  assert.equal(message.android.collapseKey, callNotificationTag('call-123'));
  assert.ok(message.android.ttl > 0 && message.android.ttl <= 30_000);
  assert.equal(
    message.apns.headers['apns-expiration'],
    String(Math.floor(expiresAt / 1000))
  );
  assert.equal(
    message.apns.headers['apns-collapse-id'],
    callNotificationTag('call-123')
  );
  assert.equal(Date.parse(message.data.expiresAt), expiresAt);
  assert.ok(Date.parse(message.data.sentAt) <= expiresAt);
});

test('answered-elsewhere reconciliation is data-only normal push', async () => {
  const pool = fakePool([
    {
      user_id: 7,
      fcm_token: 'device-a',
      source: 'device',
      capabilities: { callReconciliation: true },
    },
    { user_id: 7, fcm_token: 'legacy-old-client', source: 'legacy' },
  ]);
  const messages = [];
  const provider = fakeProvider([{ success: true }], messages);

  await sendCallReconciliationPushToUser(
    pool,
    7,
    { callId: 'call-123', chatId: '8' },
    { provider }
  );

  const message = messages[0];
  assert.deepEqual(message.tokens, ['device-a']);
  assert.equal(message.notification, undefined);
  assert.equal(message.data.type, 'call_reconcile');
  assert.equal(message.data.reason, 'answered_elsewhere');
  assert.equal(message.android.priority, 'high');
  assert.equal(message.apns.headers['apns-push-type'], 'background');
  assert.equal(message.apns.payload.aps['content-available'], 1);
});

test('provider adapter chunks fanout above the FCM multicast limit', async () => {
  const batches = [];
  const provider = {
    async sendMulticast(message) {
      batches.push(message.tokens);
      return {
        responses: message.tokens.map(() => ({ success: true })),
        successCount: message.tokens.length,
        failureCount: 0,
      };
    },
  };
  const tokens = Array.from({ length: 501 }, (_, index) => `token-${index}`);

  const result = await sendPushToTokens(
    tokens,
    'Title',
    'Body',
    {},
    { provider }
  );

  assert.deepEqual(batches.map((batch) => batch.length), [500, 1]);
  assert.equal(result.attempted, 501);
  assert.equal(result.successCount, 501);
});
