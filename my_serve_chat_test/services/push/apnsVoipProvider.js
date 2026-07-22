import apn from '@parse/node-apn';

import { appEvent, errorEvent } from '../../utils/auditLog.js';

export const APNS_VOIP_MAX_PAYLOAD_BYTES = 5 * 1024;
const DEFAULT_BUNDLE_ID = 'com.estellia.reol';
const DEFINITIVE_REASONS = new Set([
  'BadDeviceToken',
  'DeviceTokenNotForTopic',
  'Unregistered',
]);
const TRANSIENT_REASONS = new Set([
  'InternalServerError',
  'ServiceUnavailable',
  'Shutdown',
  'TooManyRequests',
]);
const TRANSIENT_STATUS_CODES = new Set([429, 500, 503]);

function normalizeEnvironment(value) {
  return value === 'development' || value === 'production' ? value : null;
}

function normalizeBundleId(value) {
  const bundleId = String(value || '').trim();
  return /^[A-Za-z0-9.-]{3,200}$/.test(bundleId)
    ? bundleId
    : DEFAULT_BUNDLE_ID;
}

function privateKeyValue(env) {
  const path = String(env.APNS_AUTH_KEY_PATH || '').trim();
  if (path) return path;
  const inline = String(env.APNS_AUTH_KEY_P8 || '').replace(/\\n/g, '\n').trim();
  return inline || null;
}

export function loadAPNsVoipConfig(env = process.env) {
  const key = privateKeyValue(env);
  const keyId = String(env.APNS_KEY_ID || '').trim();
  const teamId = String(env.APNS_TEAM_ID || '').trim();
  if (!key || !keyId || !teamId) return null;
  return {
    key,
    keyId,
    teamId,
    bundleId: normalizeBundleId(env.APNS_VOIP_BUNDLE_ID),
  };
}

export function buildVoipNotification(
  payload,
  {
    bundleId = DEFAULT_BUNDLE_ID,
    collapseId,
    notificationFactory = () => new apn.Notification(),
  } = {}
) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new TypeError('apns_voip_payload_invalid');
  }
  const rawPayload = {
    aps: { 'content-available': 1 },
    ...payload,
  };
  // Call metadata must never override the APNs envelope.
  rawPayload.aps = { 'content-available': 1 };
  const payloadBytes = Buffer.byteLength(JSON.stringify(rawPayload), 'utf8');
  if (payloadBytes > APNS_VOIP_MAX_PAYLOAD_BYTES) {
    const error = new RangeError('apns_voip_payload_too_large');
    error.code = 'apns_voip_payload_too_large';
    error.payloadBytes = payloadBytes;
    throw error;
  }

  const notification = notificationFactory();
  notification.rawPayload = rawPayload;
  notification.topic = `${normalizeBundleId(bundleId)}.voip`;
  notification.pushType = 'voip';
  notification.priority = 10;
  notification.expiry = 0;
  notification.collapseId = String(collapseId || payload.callKitUuid || payload.callId)
    .slice(0, 64);
  return { notification, payloadBytes };
}

function failureReason(failure) {
  return failure?.response?.reason || failure?.error?.reason || null;
}

function failureStatus(failure) {
  const value = Number(failure?.status);
  return Number.isFinite(value) ? value : null;
}

function isDefinitiveFailure(failure) {
  return DEFINITIVE_REASONS.has(failureReason(failure));
}

function isTransientFailure(failure) {
  return (
    TRANSIENT_STATUS_CODES.has(failureStatus(failure)) ||
    TRANSIENT_REASONS.has(failureReason(failure))
  );
}

function uniqueTargets(targets) {
  const byToken = new Map();
  for (const target of Array.isArray(targets) ? targets : []) {
    const token =
      typeof target?.token === 'string' ? target.token.trim() : '';
    const environment = normalizeEnvironment(target?.environment);
    if (!token || !environment || byToken.has(token)) continue;
    byToken.set(token, { token, environment });
  }
  return [...byToken.values()];
}

export class APNsVoipProvider {
  constructor({
    config = loadAPNsVoipConfig(),
    providerFactory = (options) => new apn.Provider(options),
    notificationFactory = () => new apn.Notification(),
    sleep = (milliseconds) =>
      new Promise((resolve) => setTimeout(resolve, milliseconds)),
    maxAttempts = 3,
  } = {}) {
    this.config = config;
    this.providerFactory = providerFactory;
    this.notificationFactory = notificationFactory;
    this.sleep = sleep;
    this.maxAttempts = Math.max(1, Math.min(4, Number(maxAttempts) || 1));
    this.providers = new Map();
  }

  get available() {
    return Boolean(this.config?.key && this.config?.keyId && this.config?.teamId);
  }

  _provider(environment) {
    if (!this.available) return null;
    if (this.providers.has(environment)) {
      return this.providers.get(environment);
    }
    const provider = this.providerFactory({
      token: {
        key: this.config.key,
        keyId: this.config.keyId,
        teamId: this.config.teamId,
      },
      production: environment === 'production',
    });
    this.providers.set(environment, provider);
    return provider;
  }

  async send(targets, payload, { collapseId } = {}) {
    const cleaned = uniqueTargets(targets);
    const summary = {
      attempted: cleaned.length,
      successCount: 0,
      failureCount: 0,
      definitiveInvalidTokens: [],
      transientFailures: 0,
      skipped: null,
      payloadBytes: 0,
    };
    if (cleaned.length === 0) {
      summary.skipped = 'no_tokens';
      return summary;
    }
    if (!this.available) {
      summary.skipped = 'provider_unavailable';
      return summary;
    }

    const built = buildVoipNotification(payload, {
      bundleId: this.config.bundleId,
      collapseId,
      notificationFactory: this.notificationFactory,
    });
    summary.payloadBytes = built.payloadBytes;

    for (const environment of ['development', 'production']) {
      let pending = cleaned
        .filter((target) => target.environment === environment)
        .map((target) => target.token);
      if (pending.length === 0) continue;
      const provider = this._provider(environment);

      for (let attempt = 1; attempt <= this.maxAttempts && pending.length > 0; attempt += 1) {
        try {
          const result = await provider.send(built.notification, pending);
          summary.successCount += result?.sent?.length || 0;
          const transient = [];
          for (const failure of result?.failed || []) {
            const token =
              typeof failure?.device === 'string' ? failure.device : null;
            if (token && isDefinitiveFailure(failure)) {
              summary.definitiveInvalidTokens.push(token);
            } else if (token && isTransientFailure(failure)) {
              transient.push(token);
            }
            appEvent('apns_voip_delivery_failure', {
              environment,
              status: failureStatus(failure),
              reason: failureReason(failure),
              definitive: isDefinitiveFailure(failure),
              transient: isTransientFailure(failure),
              attempt,
            });
          }
          if (attempt < this.maxAttempts) {
            pending = transient;
          } else {
            summary.transientFailures += transient.length;
            pending = [];
          }
        } catch (error) {
          if (attempt >= this.maxAttempts) {
            summary.transientFailures += pending.length;
            errorEvent(
              'apns_voip_provider_error',
              new Error(error?.code || error?.name || 'provider_error'),
              { environment, tokenCount: pending.length, attempt }
            );
            pending = [];
          }
        }
        if (pending.length > 0) {
          await this.sleep(Math.min(500, 75 * 2 ** (attempt - 1)));
        }
      }
    }

    summary.definitiveInvalidTokens = [
      ...new Set(summary.definitiveInvalidTokens),
    ];
    summary.failureCount =
      summary.attempted - summary.successCount;
    appEvent('apns_voip_push_result', {
      attempted: summary.attempted,
      successCount: summary.successCount,
      failureCount: summary.failureCount,
      definitiveInvalidCount: summary.definitiveInvalidTokens.length,
      transientFailures: summary.transientFailures,
      payloadBytes: summary.payloadBytes,
    });
    return summary;
  }

  shutdown() {
    for (const provider of this.providers.values()) {
      try {
        provider.shutdown();
      } catch {}
    }
    this.providers.clear();
  }
}

let providerOverride = null;
let defaultProvider = null;

export function getAPNsVoipProvider() {
  if (providerOverride) return providerOverride;
  defaultProvider ??= new APNsVoipProvider();
  return defaultProvider;
}

export function setAPNsVoipProviderForTests(provider) {
  providerOverride = provider || null;
  defaultProvider?.shutdown();
  defaultProvider = null;
}
