const OPTIONAL_REGISTRY_ERROR_CODES = new Set(['42P01', '42703']);

function isOptionalRegistryError(error) {
  return OPTIONAL_REGISTRY_ERROR_CODES.has(error?.code);
}

function normalizeUserIds(userIds) {
  return [...new Set(
    (Array.isArray(userIds) ? userIds : [userIds])
      .map((value) => Number.parseInt(String(value), 10))
      .filter((value) => Number.isSafeInteger(value) && value > 0)
  )];
}

async function inTransaction(pool, operation) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await operation(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {}
    throw error;
  } finally {
    client.release();
  }
}

export async function upsertPushDevice(
  pool,
  {
    installationId,
    userId,
    platform,
    fcmToken,
    apnsVoipToken,
    apnsEnvironment,
    capabilities = {},
    appVersion = null,
  }
) {
  const hasFcmToken = fcmToken !== undefined;
  const hasVoipToken = apnsVoipToken !== undefined;
  const hasApnsEnvironment = apnsEnvironment !== undefined;

  return inTransaction(pool, async (client) => {
    if (typeof fcmToken === 'string' && fcmToken.length > 0) {
      await client.query(
        'SELECT pg_advisory_xact_lock(hashtext($1))',
        [`fcm:${fcmToken}`]
      );
      // A provider token can only have one owner. This also repairs stale rows
      // created after reinstall/restore before the unique index was present.
      await client.query(
        `UPDATE push_devices
         SET fcm_token = NULL,
             disabled_at = CASE
               WHEN apns_voip_token IS NULL
                 THEN COALESCE(disabled_at, CURRENT_TIMESTAMP)
               ELSE disabled_at
             END,
             updated_at = CURRENT_TIMESTAMP
         WHERE fcm_token = $1 AND installation_id <> $2`,
        [fcmToken, installationId]
      );
      // Once a new client claims this token, the normalized registry is
      // authoritative. Leaving a legacy copy on another account would leak
      // that account's notifications after an account switch.
      await client.query(
        'UPDATE users SET fcm_token = NULL WHERE fcm_token = $1',
        [fcmToken]
      );
    }

    if (typeof apnsVoipToken === 'string' && apnsVoipToken.length > 0) {
      await client.query(
        'SELECT pg_advisory_xact_lock(hashtext($1))',
        [`voip:${apnsVoipToken}`]
      );
      await client.query(
        `UPDATE push_devices
         SET apns_voip_token = NULL,
             apns_environment = NULL,
             disabled_at = CASE
               WHEN fcm_token IS NULL
                 THEN COALESCE(disabled_at, CURRENT_TIMESTAMP)
               ELSE disabled_at
             END,
             updated_at = CURRENT_TIMESTAMP
         WHERE apns_voip_token = $1 AND installation_id <> $2`,
        [apnsVoipToken, installationId]
      );
    }

    const result = await client.query(
      `INSERT INTO push_devices (
         installation_id,
         user_id,
         platform,
         fcm_token,
         apns_voip_token,
         apns_environment,
         capabilities,
         app_version,
         created_at,
         updated_at,
         last_seen_at,
         disabled_at
       )
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, NULL)
       ON CONFLICT (installation_id) DO UPDATE
       SET user_id = EXCLUDED.user_id,
           platform = EXCLUDED.platform,
           fcm_token = CASE WHEN $9::boolean THEN EXCLUDED.fcm_token ELSE push_devices.fcm_token END,
           apns_voip_token = CASE WHEN $10::boolean THEN EXCLUDED.apns_voip_token ELSE push_devices.apns_voip_token END,
           apns_environment = CASE WHEN $11::boolean THEN EXCLUDED.apns_environment ELSE push_devices.apns_environment END,
           capabilities = EXCLUDED.capabilities,
           app_version = EXCLUDED.app_version,
           updated_at = CURRENT_TIMESTAMP,
           last_seen_at = CURRENT_TIMESTAMP,
           disabled_at = NULL
       RETURNING installation_id, user_id, platform, capabilities, app_version,
                 created_at, updated_at, last_seen_at, disabled_at`,
      [
        installationId,
        userId,
        platform,
        fcmToken ?? null,
        apnsVoipToken ?? null,
        apnsEnvironment ?? null,
        JSON.stringify(capabilities),
        appVersion,
        hasFcmToken,
        hasVoipToken,
        hasApnsEnvironment,
      ]
    );
    // Keep users.fcm_token as a dual-read safety net for old fanout paths and
    // for the window before push_devices is fully populated.
    if (hasFcmToken && typeof fcmToken === 'string' && fcmToken.length > 0) {
      await client.query('UPDATE users SET fcm_token = $1 WHERE id = $2', [
        fcmToken,
        userId,
      ]);
    }
    return result.rows[0] || null;
  });
}

export async function disablePushDevice(pool, { installationId, userId }) {
  const result = await pool.query(
    `UPDATE push_devices
     SET fcm_token = NULL,
         apns_voip_token = NULL,
         apns_environment = NULL,
         disabled_at = COALESCE(disabled_at, CURRENT_TIMESTAMP),
         updated_at = CURRENT_TIMESTAMP,
         last_seen_at = CURRENT_TIMESTAMP
     WHERE installation_id = $1 AND user_id = $2
     RETURNING installation_id`,
    [installationId, userId]
  );
  return result.rows.length > 0;
}

export async function claimLegacyFcmToken(pool, { userId, fcmToken }) {
  return inTransaction(pool, async (client) => {
    if (!fcmToken) {
      const previous = await client.query(
        'SELECT fcm_token FROM users WHERE id = $1 FOR UPDATE',
        [userId]
      );
      await client.query('UPDATE users SET fcm_token = NULL WHERE id = $1', [
        userId,
      ]);
      const previousToken = previous.rows[0]?.fcm_token;
      if (previousToken) {
        const registry = await client.query(
          `SELECT to_regclass('public.push_devices') AS table_name`
        );
        if (registry.rows[0]?.table_name) {
          await client.query(
            `UPDATE push_devices
             SET fcm_token = NULL,
                 disabled_at = CASE
                   WHEN apns_voip_token IS NULL
                     THEN COALESCE(disabled_at, CURRENT_TIMESTAMP)
                   ELSE disabled_at
                 END,
                 updated_at = CURRENT_TIMESTAMP
             WHERE user_id = $1 AND fcm_token = $2`,
            [userId, previousToken]
          );
        }
      }
      return;
    }

    await client.query(
      'SELECT pg_advisory_xact_lock(hashtext($1))',
      [`fcm:${fcmToken}`]
    );
    // During rolling deployment the additive migration may not exist yet.
    // Once a normalized installation owns a token, legacy requests must not
    // steal it back (for example, a delayed request from the previous account).
    const registry = await client.query(
      `SELECT to_regclass('public.push_devices') AS table_name`
    );
    if (registry.rows[0]?.table_name) {
      const normalizedOwner = await client.query(
        `SELECT user_id
         FROM push_devices
         WHERE fcm_token = $1 AND disabled_at IS NULL
         FOR UPDATE`,
        [fcmToken]
      );
      if (normalizedOwner.rows.length > 0) {
        await client.query(
          `UPDATE users
           SET fcm_token = NULL
           WHERE fcm_token = $1 OR id = $2`,
          [fcmToken, userId]
        );
        return;
      }
    }

    await client.query(
      'UPDATE users SET fcm_token = NULL WHERE fcm_token = $1 AND id <> $2',
      [fcmToken, userId]
    );
    await client.query('UPDATE users SET fcm_token = $1 WHERE id = $2', [
      fcmToken,
      userId,
    ]);
  });
}

async function queryLegacyTokens(pool, userIds) {
  return pool.query(
    `SELECT id AS user_id, fcm_token, 'legacy' AS source,
            'legacy' AS platform, NULL::text AS apns_voip_token,
            NULL::text AS apns_environment
     FROM users
     WHERE id = ANY($1::int[])
       AND fcm_token IS NOT NULL
       AND fcm_token <> ''`,
    [userIds]
  );
}

export async function getActivePushTokensForUsers(pool, userIds) {
  const ids = normalizeUserIds(userIds);
  if (ids.length === 0) return [];

  let result;
  try {
    result = await pool.query(
      `SELECT pd.user_id, pd.fcm_token, 'device' AS source, pd.capabilities,
              pd.platform, pd.apns_voip_token, pd.apns_environment
       FROM push_devices pd
       WHERE pd.user_id = ANY($1::int[])
         AND pd.disabled_at IS NULL
         AND pd.fcm_token IS NOT NULL
         AND pd.fcm_token <> ''
       UNION ALL
       SELECT u.id AS user_id, u.fcm_token, 'legacy' AS source,
              '{}'::jsonb AS capabilities, 'legacy' AS platform,
              NULL::text AS apns_voip_token,
              NULL::text AS apns_environment
       FROM users u
       WHERE u.id = ANY($1::int[])
         AND u.fcm_token IS NOT NULL
         AND u.fcm_token <> ''
         AND NOT EXISTS (
           SELECT 1
           FROM push_devices owner
           WHERE owner.fcm_token = u.fcm_token
             AND owner.disabled_at IS NULL
         )`,
      [ids]
    );
  } catch (error) {
    if (!isOptionalRegistryError(error)) throw error;
    result = await queryLegacyTokens(pool, ids);
  }

  const byToken = new Map();
  for (const row of result.rows) {
    const token = typeof row.fcm_token === 'string' ? row.fcm_token.trim() : '';
    if (!token || byToken.has(token)) continue;
    byToken.set(token, {
      token,
      userId: row.user_id?.toString() ?? null,
      source: row.source === 'device' ? 'device' : 'legacy',
      capabilities:
        row.capabilities && typeof row.capabilities === 'object'
          ? row.capabilities
          : {},
      platform: row.platform?.toString() || 'legacy',
      hasVoipToken:
        typeof row.apns_voip_token === 'string' &&
        row.apns_voip_token.trim().length > 0 &&
        (row.apns_environment === 'development' ||
          row.apns_environment === 'production') &&
        row.capabilities?.voipPush === true,
    });
  }
  return [...byToken.values()];
}

export async function getActiveVoipTargetsForUsers(pool, userIds) {
  const ids = normalizeUserIds(userIds);
  if (ids.length === 0) return [];
  let result;
  try {
    result = await pool.query(
      `SELECT user_id, installation_id, apns_voip_token, apns_environment,
              capabilities
         FROM push_devices
        WHERE user_id = ANY($1::int[])
          AND platform = 'ios'
          AND disabled_at IS NULL
          AND apns_voip_token IS NOT NULL
          AND apns_voip_token <> ''
          AND apns_environment IN ('development', 'production')
          AND capabilities @> '{"voipPush": true}'::jsonb`,
      [ids]
    );
  } catch (error) {
    if (!isOptionalRegistryError(error)) throw error;
    return [];
  }
  const byToken = new Map();
  for (const row of result.rows) {
    const token =
      typeof row.apns_voip_token === 'string'
        ? row.apns_voip_token.trim()
        : '';
    const environment = row.apns_environment;
    if (
      !token ||
      byToken.has(token) ||
      (environment !== 'development' && environment !== 'production')
    ) {
      continue;
    }
    byToken.set(token, {
      token,
      environment,
      userId: row.user_id?.toString() ?? null,
      installationId: row.installation_id?.toString() ?? null,
      capabilities:
        row.capabilities && typeof row.capabilities === 'object'
          ? row.capabilities
          : {},
    });
  }
  return [...byToken.values()];
}

export async function pruneInvalidPushTokens(pool, tokens) {
  const cleaned = [...new Set(
    (Array.isArray(tokens) ? tokens : [])
      .filter((token) => typeof token === 'string')
      .map((token) => token.trim())
      .filter(Boolean)
  )];
  if (cleaned.length === 0) return { devices: 0, legacy: 0 };

  let devices = 0;
  try {
    const result = await pool.query(
      `UPDATE push_devices
       SET fcm_token = NULL,
           disabled_at = CASE
             WHEN apns_voip_token IS NULL
               THEN COALESCE(disabled_at, CURRENT_TIMESTAMP)
             ELSE disabled_at
           END,
           updated_at = CURRENT_TIMESTAMP
       WHERE fcm_token = ANY($1::text[])`,
      [cleaned]
    );
    devices = result.rowCount || 0;
  } catch (error) {
    if (!isOptionalRegistryError(error)) throw error;
  }

  const legacyResult = await pool.query(
    'UPDATE users SET fcm_token = NULL WHERE fcm_token = ANY($1::text[])',
    [cleaned]
  );
  return { devices, legacy: legacyResult.rowCount || 0 };
}

export async function pruneInvalidVoipTokens(pool, tokens) {
  const cleaned = [...new Set(
    (Array.isArray(tokens) ? tokens : [])
      .filter((token) => typeof token === 'string')
      .map((token) => token.trim())
      .filter(Boolean)
  )];
  if (cleaned.length === 0) return 0;
  try {
    const result = await pool.query(
      `UPDATE push_devices
       SET apns_voip_token = NULL,
           apns_environment = NULL,
           disabled_at = CASE
             WHEN fcm_token IS NULL
               THEN COALESCE(disabled_at, CURRENT_TIMESTAMP)
             ELSE disabled_at
           END,
           updated_at = CURRENT_TIMESTAMP
       WHERE apns_voip_token = ANY($1::text[])`,
      [cleaned]
    );
    return result.rowCount || 0;
  } catch (error) {
    if (!isOptionalRegistryError(error)) throw error;
    return 0;
  }
}
