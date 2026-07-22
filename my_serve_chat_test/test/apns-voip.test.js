import assert from 'node:assert/strict';
import test from 'node:test';

import {
  APNS_VOIP_MAX_PAYLOAD_BYTES,
  APNsVoipProvider,
  buildVoipNotification,
  loadAPNsVoipConfig,
} from '../services/push/apnsVoipProvider.js';
import { sendIncomingCallPushToUser } from '../utils/pushNotifications.js';

test('VoIP notification uses mandatory APNs headers and a bounded payload', () => {
  const fake = {};
  const { notification, payloadBytes } = buildVoipNotification(
    {
      type: 'incoming_call',
      callId: 'call-1',
      callKitUuid: '123e4567-e89b-42d3-a456-426614174000',
      chatId: '8',
      fromLabel: 'Caller',
    },
    {
      bundleId: 'com.estellia.reol',
      collapseId: 'call-collapse',
      notificationFactory: () => fake,
    }
  );

  assert.equal(notification, fake);
  assert.equal(fake.topic, 'com.estellia.reol.voip');
  assert.equal(fake.pushType, 'voip');
  assert.equal(fake.priority, 10);
  assert.equal(fake.expiry, 0);
  assert.equal(fake.collapseId, 'call-collapse');
  assert.deepEqual(fake.rawPayload.aps, { 'content-available': 1 });
  assert.ok(payloadBytes > 0 && payloadBytes <= APNS_VOIP_MAX_PAYLOAD_BYTES);
  assert.equal('participantToken' in fake.rawPayload, false);
  assert.equal('authToken' in fake.rawPayload, false);
});

test('VoIP notification rejects payloads above the APNs 5KB limit', () => {
  assert.throws(
    () =>
      buildVoipNotification(
        { type: 'incoming_call', oversized: 'x'.repeat(6000) },
        { notificationFactory: () => ({}) }
      ),
    (error) => error?.code === 'apns_voip_payload_too_large'
  );
});

test('provider routes sandbox/production and retries only transient failures', async () => {
  const providerOptions = [];
  const sends = [];
  const attempts = new Map();
  const adapter = new APNsVoipProvider({
    config: {
      key: 'test-key-placeholder',
      keyId: 'TESTKEY',
      teamId: 'TESTTEAM',
      bundleId: 'com.estellia.reol',
    },
    providerFactory(options) {
      providerOptions.push(options);
      return {
        async send(_notification, tokens) {
          sends.push({ production: options.production, tokens: [...tokens] });
          const key = options.production ? 'production' : 'development';
          const attempt = (attempts.get(key) || 0) + 1;
          attempts.set(key, attempt);
          if (!options.production && attempt === 1) {
            return {
              sent: [{ device: 'dev-ok' }],
              failed: [
                {
                  device: 'dev-invalid',
                  status: 410,
                  response: { reason: 'Unregistered' },
                },
                {
                  device: 'dev-retry',
                  status: 503,
                  response: { reason: 'ServiceUnavailable' },
                },
              ],
            };
          }
          return {
            sent: tokens.map((device) => ({ device })),
            failed: [],
          };
        },
        shutdown() {},
      };
    },
    notificationFactory: () => ({}),
    sleep: async () => {},
  });

  const result = await adapter.send(
    [
      { token: 'dev-ok', environment: 'development' },
      { token: 'dev-invalid', environment: 'development' },
      { token: 'dev-retry', environment: 'development' },
      { token: 'prod-ok', environment: 'production' },
    ],
    {
      type: 'incoming_call',
      callId: 'call-1',
      callKitUuid: '123e4567-e89b-42d3-a456-426614174000',
      chatId: '8',
    }
  );

  assert.deepEqual(
    providerOptions.map((options) => options.production).sort(),
    [false, true]
  );
  assert.deepEqual(sends[1], {
    production: false,
    tokens: ['dev-retry'],
  });
  assert.deepEqual(result.definitiveInvalidTokens, ['dev-invalid']);
  assert.equal(result.successCount, 3);
  assert.equal(result.failureCount, 1);
});

test('incoming call prunes definitive VoIP token and does not duplicate iOS FCM', async () => {
  const updates = [];
  const fcmMessages = [];
  const pool = {
    async query(sql, params) {
      if (/SELECT user_id, installation_id, apns_voip_token/.test(sql)) {
        return {
          rows: [
            {
              user_id: 7,
              installation_id: 'install-1',
              apns_voip_token: 'invalid-voip',
              apns_environment: 'development',
              capabilities: { voipPush: true },
            },
          ],
        };
      }
      if (/SELECT pd\.user_id/.test(sql)) {
        return {
          rows: [
            {
              user_id: 7,
              fcm_token: 'ios-fcm',
              source: 'device',
              platform: 'ios',
              apns_voip_token: 'invalid-voip',
              apns_environment: 'development',
              capabilities: {
                voipPush: true,
                callPayloadVersion: 2,
              },
            },
          ],
        };
      }
      if (/SET apns_voip_token = NULL/.test(sql)) {
        updates.push(params);
        return { rows: [], rowCount: 1 };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    },
  };
  const apnsVoipProvider = {
    async send() {
      return {
        attempted: 1,
        successCount: 0,
        failureCount: 1,
        definitiveInvalidTokens: ['invalid-voip'],
      };
    },
  };
  const fcmProvider = {
    async sendMulticast(message) {
      fcmMessages.push(message);
      return { sent: [], responses: [], successCount: 0, failureCount: 0 };
    },
  };

  const result = await sendIncomingCallPushToUser(
    pool,
    7,
    {
      callId: 'call-1',
      callKitUuid: '123e4567-e89b-42d3-a456-426614174000',
      chatId: '8',
      chatName: 'DM',
      fromUserId: '6',
      fromEmail: 'Caller',
      mediaType: 'audio',
      expiresAt: Date.now() + 30_000,
    },
    { provider: fcmProvider, apnsVoipProvider }
  );

  assert.equal(result.voipTargetCount, 1);
  assert.equal(fcmMessages.length, 0);
  assert.deepEqual(updates, [[['invalid-voip']]]);
});

test('APNs token auth config uses placeholders and remains optional', () => {
  assert.equal(loadAPNsVoipConfig({}), null);
  assert.deepEqual(
    loadAPNsVoipConfig({
      APNS_AUTH_KEY_PATH: '/run/secrets/AuthKey_TEST.p8',
      APNS_KEY_ID: 'KEYID',
      APNS_TEAM_ID: 'TEAMID',
      APNS_VOIP_BUNDLE_ID: 'com.estellia.reol',
    }),
    {
      key: '/run/secrets/AuthKey_TEST.p8',
      keyId: 'KEYID',
      teamId: 'TEAMID',
      bundleId: 'com.estellia.reol',
    }
  );
});
