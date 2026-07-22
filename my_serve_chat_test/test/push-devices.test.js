import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  createPushDevicesController,
  parsePushDeviceUpsert,
} from '../controllers/pushDevicesController.js';
import {
  claimLegacyFcmToken,
  disablePushDevice,
  upsertPushDevice,
} from '../repositories/pushDevicesRepository.js';

const installationId = '123e4567-e89b-42d3-a456-426614174000';

function responseRecorder() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    },
    send(value) {
      this.body = value;
      return this;
    },
  };
}

test('push_devices migration is additive and preserves legacy token', async () => {
  const sql = await readFile(
    new URL('../migrations/add_push_devices.sql', import.meta.url),
    'utf8'
  );
  assert.match(sql, /CREATE TABLE IF NOT EXISTS push_devices/i);
  assert.match(sql, /installation_id VARCHAR\(128\) PRIMARY KEY/i);
  assert.match(sql, /REFERENCES users\(id\) ON DELETE CASCADE/i);
  assert.match(sql, /apns_voip_token TEXT NULL/i);
  assert.match(sql, /disabled_at TIMESTAMPTZ NULL/i);
  assert.match(sql, /ux_push_devices_fcm_token/i);
  assert.doesNotMatch(sql, /DROP\s+(COLUMN|TABLE)/i);
  assert.doesNotMatch(sql, /ALTER\s+TABLE\s+users/i);
});

test('device payload parser supports normal push and future VoIP shape', () => {
  const normal = parsePushDeviceUpsert({
    installationId,
    platform: 'ios',
    tokens: { fcm: 'normal-token' },
    capabilities: {
      normalPush: true,
      voipPush: false,
      callPayloadVersion: 2,
    },
    appVersion: '1.0.0+4',
  });
  assert.equal(normal.ok, true);
  assert.equal(normal.value.fcmToken, 'normal-token');
  assert.equal(normal.value.apnsVoipToken, undefined);

  const voip = parsePushDeviceUpsert({
    installationId,
    platform: 'ios',
    tokens: {
      fcm: 'normal-token',
      apnsVoip: 'future-voip-token',
      apnsEnvironment: 'development',
    },
  });
  assert.equal(voip.ok, true);
  assert.equal(voip.value.apnsEnvironment, 'development');

  assert.equal(
    parsePushDeviceUpsert({
      installationId,
      platform: 'android',
      tokens: {
        apnsVoip: 'not-allowed',
        apnsEnvironment: 'production',
      },
    }).ok,
    false
  );
});

test('controller takes ownership only from JWT and delete is owner-scoped', async () => {
  const calls = [];
  const repository = {
    async upsertPushDevice(_pool, input) {
      calls.push({ operation: 'upsert', input });
      return {
        installation_id: input.installationId,
        user_id: input.userId,
        platform: input.platform,
        capabilities: input.capabilities,
        app_version: input.appVersion,
      };
    },
    async disablePushDevice(_pool, input) {
      calls.push({ operation: 'delete', input });
      return true;
    },
  };
  const controller = createPushDevicesController({
    pool: {},
    repository,
  });

  const upsertResponse = responseRecorder();
  await controller.upsertCurrent(
    {
      user: { userId: 7 },
      body: {
        userId: 999,
        installationId,
        platform: 'android',
        tokens: { fcm: 'normal-token' },
      },
    },
    upsertResponse
  );
  assert.equal(upsertResponse.statusCode, 200);
  assert.equal(calls[0].input.userId, 7);
  assert.equal(calls[0].input.installationId, installationId);

  const deleteResponse = responseRecorder();
  await controller.deleteCurrent(
    {
      user: { userId: 7 },
      body: { installationId, userId: 999 },
      get: () => null,
    },
    deleteResponse
  );
  assert.equal(deleteResponse.statusCode, 204);
  assert.deepEqual(calls[1].input, { installationId, userId: 7 });
});

test('repository upsert is transactional and transfers installation owner', async () => {
  const statements = [];
  const client = {
    async query(sql, params = []) {
      statements.push({ sql, params });
      if (/RETURNING installation_id/.test(sql)) {
        return {
          rows: [
            {
              installation_id: installationId,
              user_id: params[1],
              platform: params[2],
            },
          ],
        };
      }
      return { rows: [], rowCount: 0 };
    },
    release() {
      statements.push({ sql: 'RELEASE', params: [] });
    },
  };
  const pool = { connect: async () => client };

  const result = await upsertPushDevice(pool, {
    installationId,
    userId: 42,
    platform: 'android',
    fcmToken: 'normal-token',
    capabilities: { normalPush: true },
    appVersion: '1.0.0+4',
  });

  assert.equal(result.user_id, 42);
  assert.equal(statements[0].sql, 'BEGIN');
  assert.match(
    statements.find((entry) => /INSERT INTO push_devices/.test(entry.sql)).sql,
    /ON CONFLICT \(installation_id\) DO UPDATE/
  );
  assert.match(
    statements.find((entry) => /INSERT INTO push_devices/.test(entry.sql)).sql,
    /user_id = EXCLUDED\.user_id/
  );
  assert.equal(statements.at(-2).sql, 'COMMIT');
  assert.equal(statements.at(-1).sql, 'RELEASE');
});

test('repository delete cannot disable another account installation', async () => {
  let captured;
  const pool = {
    async query(sql, params) {
      captured = { sql, params };
      return { rows: [], rowCount: 0 };
    },
  };
  const changed = await disablePushDevice(pool, {
    installationId,
    userId: 55,
  });
  assert.equal(changed, false);
  assert.match(captured.sql, /installation_id = \$1 AND user_id = \$2/);
  assert.deepEqual(captured.params, [installationId, 55]);
});

test('delayed legacy update cannot steal a normalized token owner', async () => {
  const statements = [];
  const client = {
    async query(sql, params = []) {
      statements.push({ sql, params });
      if (/to_regclass/.test(sql)) {
        return { rows: [{ table_name: 'push_devices' }] };
      }
      if (/SELECT user_id[\s\S]*FROM push_devices/.test(sql)) {
        return { rows: [{ user_id: 99 }] };
      }
      return { rows: [], rowCount: 1 };
    },
    release() {},
  };

  await claimLegacyFcmToken(
    { connect: async () => client },
    { userId: 7, fcmToken: 'normalized-token' }
  );

  assert.equal(
    statements.some((entry) => /SET user_id =/.test(entry.sql)),
    false
  );
  assert.equal(
    statements.some(
      (entry) =>
        /UPDATE users/.test(entry.sql) &&
        /fcm_token = NULL/.test(entry.sql)
    ),
    true
  );
  assert.equal(statements.at(-1).sql, 'COMMIT');
});
