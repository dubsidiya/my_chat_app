import crypto from 'crypto';

const MAX_IDEMPOTENCY_KEY_LEN = 200;

const isIdempotencyStorageUnavailable = (error) => {
  const code = error?.code;
  // 42P01: relation does not exist
  // 42703: column does not exist
  // 42P16: invalid table definition / incompatible schema
  // 42501: insufficient_privilege
  return code === '42P01' || code === '42703' || code === '42P16' || code === '42501';
};

const stableStringify = (value) => {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((v) => stableStringify(v)).join(',')}]`;
  }
  const keys = Object.keys(value).sort();
  const parts = keys.map((k) => `${JSON.stringify(k)}:${stableStringify(value[k])}`);
  return `{${parts.join(',')}}`;
};

export const getIdempotencyKey = (req) => {
  const fromHeader =
    req?.headers?.['idempotency-key'] ??
    req?.headers?.['Idempotency-Key'] ??
    null;
  const fromBody = req?.body?.idempotency_key;
  const raw = (fromHeader || fromBody || '').toString().trim();
  if (!raw) return null;
  return raw.substring(0, MAX_IDEMPOTENCY_KEY_LEN);
};

export const hashIdempotencyPayload = (payload) => {
  const text = stableStringify(payload);
  return crypto.createHash('sha256').update(text).digest('hex');
};

export const beginIdempotent = async (client, { userId, scope, key, requestHash }) => {
  if (!key) return { enabled: false };
  try {
    await client.query(
      'DELETE FROM idempotency_keys WHERE expires_at < CURRENT_TIMESTAMP'
    );
    const existing = await client.query(
      `SELECT status, request_hash, response_status, response_body
       FROM idempotency_keys
       WHERE user_id = $1 AND scope = $2 AND idempotency_key = $3
       FOR UPDATE`,
      [userId, scope, key]
    );
    if (existing.rows.length > 0) {
      const row = existing.rows[0];
      if (row.request_hash !== requestHash) {
        return { enabled: true, conflict: 'Этот idempotency key уже использован для другого запроса' };
      }
      if (row.status === 'completed') {
        return {
          enabled: true,
          replay: true,
          responseStatus: row.response_status || 200,
          responseBody: row.response_body || {},
        };
      }
      return { enabled: true, conflict: 'Запрос с этим idempotency key уже выполняется' };
    }
    await client.query(
      `INSERT INTO idempotency_keys (user_id, scope, idempotency_key, request_hash, status)
       VALUES ($1, $2, $3, $4, 'pending')`,
      [userId, scope, key, requestHash]
    );
    return { enabled: true };
  } catch (error) {
    if (isIdempotencyStorageUnavailable(error)) {
      console.warn('Idempotency storage unavailable, request will proceed without idempotency checks');
      return { enabled: false };
    }
    throw error;
  }
};

export const completeIdempotent = async (
  client,
  { userId, scope, key, responseStatus, responseBody }
) => {
  if (!key) return;
  try {
    await client.query(
      `UPDATE idempotency_keys
       SET status = 'completed',
           response_status = $4,
           response_body = $5::jsonb,
           completed_at = CURRENT_TIMESTAMP,
           expires_at = CURRENT_TIMESTAMP + interval '24 hours'
       WHERE user_id = $1 AND scope = $2 AND idempotency_key = $3 AND status = 'pending'`,
      [
        userId,
        scope,
        key,
        responseStatus,
        JSON.stringify(responseBody ?? {}),
      ]
    );
  } catch (error) {
    if (isIdempotencyStorageUnavailable(error)) {
      return;
    }
    throw error;
  }
};
