import {
  claimLegacyFcmToken,
  disablePushDevice,
  upsertPushDevice,
} from '../repositories/pushDevicesRepository.js';

const ALLOWED_PLATFORMS = new Set([
  'android',
  'ios',
  'web',
  'macos',
  'windows',
  'linux',
  'unknown',
]);
const INSTALLATION_ID_RE = /^[A-Za-z0-9._:-]{16,128}$/;

function hasOwn(value, key) {
  return Boolean(
    value &&
      typeof value === 'object' &&
      Object.prototype.hasOwnProperty.call(value, key)
  );
}

function normalizeOptionalToken(value, maxLength, fieldName) {
  if (value == null) return { ok: true, value: null };
  if (typeof value !== 'string') {
    return { ok: false, message: `${fieldName} должен быть строкой или null` };
  }
  const normalized = value.trim();
  if (!normalized) return { ok: true, value: null };
  if (normalized.length > maxLength) {
    return {
      ok: false,
      message: `${fieldName} не более ${maxLength} символов`,
    };
  }
  if (!/^[\x21-\x7E]+$/.test(normalized)) {
    return { ok: false, message: `${fieldName} содержит недопустимые символы` };
  }
  return { ok: true, value: normalized };
}

function normalizeCapabilities(value) {
  if (value == null) return { ok: true, value: {} };
  if (
    typeof value !== 'object' ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    return { ok: false, message: 'capabilities должен быть JSON-объектом' };
  }
  const normalized = {};
  for (const [key, entry] of Object.entries(value)) {
    if (!/^[A-Za-z0-9_.-]{1,64}$/.test(key)) {
      return { ok: false, message: 'Некорректный ключ capabilities' };
    }
    if (
      entry !== null &&
      typeof entry !== 'boolean' &&
      typeof entry !== 'string' &&
      typeof entry !== 'number'
    ) {
      return {
        ok: false,
        message: 'Значения capabilities должны быть примитивами',
      };
    }
    if (typeof entry === 'string' && entry.length > 128) {
      return { ok: false, message: 'Значение capabilities слишком длинное' };
    }
    normalized[key] = entry;
  }
  if (JSON.stringify(normalized).length > 4096) {
    return { ok: false, message: 'capabilities слишком большой' };
  }
  return { ok: true, value: normalized };
}

export function parsePushDeviceUpsert(body = {}) {
  const installationId = (
    body.installationId ??
    body.installation_id ??
    ''
  ).toString().trim();
  if (!INSTALLATION_ID_RE.test(installationId)) {
    return {
      ok: false,
      message: 'Некорректный installationId',
    };
  }

  const platform = (body.platform ?? '').toString().trim().toLowerCase();
  if (!ALLOWED_PLATFORMS.has(platform)) {
    return { ok: false, message: 'Некорректная platform' };
  }

  const tokens =
    body.tokens && typeof body.tokens === 'object' && !Array.isArray(body.tokens)
      ? body.tokens
      : {};
  const hasFcmToken = hasOwn(tokens, 'fcm') || hasOwn(body, 'fcmToken');
  const hasVoipToken =
    hasOwn(tokens, 'apnsVoip') || hasOwn(body, 'apnsVoipToken');
  const hasApnsEnvironment =
    hasOwn(tokens, 'apnsEnvironment') || hasOwn(body, 'apnsEnvironment');
  if (!hasFcmToken && !hasVoipToken) {
    return { ok: false, message: 'Укажите normal или VoIP push token' };
  }

  const fcm = normalizeOptionalToken(
    hasOwn(tokens, 'fcm') ? tokens.fcm : body.fcmToken,
    2048,
    'tokens.fcm'
  );
  if (!fcm.ok) return fcm;
  const voip = normalizeOptionalToken(
    hasOwn(tokens, 'apnsVoip')
      ? tokens.apnsVoip
      : body.apnsVoipToken,
    512,
    'tokens.apnsVoip'
  );
  if (!voip.ok) return voip;

  let apnsEnvironment;
  if (hasApnsEnvironment) {
    const raw = (
      hasOwn(tokens, 'apnsEnvironment')
        ? tokens.apnsEnvironment
        : body.apnsEnvironment
    );
    apnsEnvironment = raw == null ? null : raw.toString().trim().toLowerCase();
    if (
      apnsEnvironment != null &&
      apnsEnvironment !== 'development' &&
      apnsEnvironment !== 'production'
    ) {
      return { ok: false, message: 'Некорректная APNs environment' };
    }
  }
  if (hasVoipToken || hasApnsEnvironment) {
    if (!hasVoipToken || !hasApnsEnvironment) {
      return {
        ok: false,
        message: 'VoIP token и APNs environment должны обновляться вместе',
      };
    }
    if ((voip.value == null) !== (apnsEnvironment == null)) {
      return {
        ok: false,
        message: 'VoIP token требует APNs environment',
      };
    }
    if (voip.value != null && platform !== 'ios') {
      return { ok: false, message: 'VoIP token поддерживается только на iOS' };
    }
  }

  const capabilities = normalizeCapabilities(body.capabilities);
  if (!capabilities.ok) return capabilities;

  const appVersion =
    body.appVersion == null ? null : body.appVersion.toString().trim();
  if (appVersion != null && appVersion.length > 64) {
    return { ok: false, message: 'appVersion не более 64 символов' };
  }

  return {
    ok: true,
    value: {
      installationId,
      platform,
      fcmToken: hasFcmToken ? fcm.value : undefined,
      apnsVoipToken: hasVoipToken ? voip.value : undefined,
      apnsEnvironment: hasApnsEnvironment ? apnsEnvironment : undefined,
      capabilities: capabilities.value,
      appVersion: appVersion || null,
    },
  };
}

export function parseInstallationId(body = {}, headerValue) {
  const installationId = (
    body.installationId ??
    body.installation_id ??
    headerValue ??
    ''
  ).toString().trim();
  return INSTALLATION_ID_RE.test(installationId) ? installationId : null;
}

export function createPushDevicesController({
  pool,
  repository = { upsertPushDevice, disablePushDevice },
}) {
  const upsertCurrent = async (req, res) => {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }
    const parsed = parsePushDeviceUpsert(req.body || {});
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    try {
      const row = await repository.upsertPushDevice(pool, {
        ...parsed.value,
        // Ownership always comes from the verified JWT, never request JSON.
        userId,
      });
      return res.status(200).json({
        installationId: row?.installation_id ?? parsed.value.installationId,
        platform: row?.platform ?? parsed.value.platform,
        capabilities: row?.capabilities ?? parsed.value.capabilities,
        appVersion: row?.app_version ?? parsed.value.appVersion,
        lastSeenAt: row?.last_seen_at ?? null,
        disabledAt: row?.disabled_at ?? null,
      });
    } catch (error) {
      console.error('push device upsert failed', {
        code: error?.code || 'unknown',
      });
      // Schema not ready yet: keep legacy users.fcm_token path alive so
      // message/call pushes do not go dark after an incomplete deploy.
      if (error?.code === '42P01' || error?.code === '42703') {
        const fcm =
          typeof parsed.value.fcmToken === 'string'
            ? parsed.value.fcmToken.trim()
            : '';
        if (fcm) {
          try {
            await claimLegacyFcmToken(pool, { userId, fcmToken: fcm });
            return res.status(200).json({
              installationId: parsed.value.installationId,
              platform: parsed.value.platform,
              capabilities: parsed.value.capabilities,
              appVersion: parsed.value.appVersion,
              legacyFallback: true,
            });
          } catch (legacyError) {
            console.error('legacy fcm fallback failed', {
              code: legacyError?.code || 'unknown',
            });
          }
        }
        return res.status(503).json({
          message: 'Реестр push-устройств ещё не готов',
        });
      }
      return res.status(500).json({ message: 'Ошибка сервера' });
    }
  };

  const deleteCurrent = async (req, res) => {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }
    const installationId = parseInstallationId(
      req.body || {},
      req.get?.('x-installation-id')
    );
    if (!installationId) {
      return res.status(400).json({ message: 'Некорректный installationId' });
    }

    try {
      // The user predicate prevents a delayed logout from account A from
      // disabling an installation already transferred to account B.
      await repository.disablePushDevice(pool, { installationId, userId });
      return res.status(204).send();
    } catch (error) {
      console.error('push device delete failed', {
        code: error?.code || 'unknown',
      });
      if (error?.code === '42P01') {
        return res.status(204).send();
      }
      return res.status(500).json({ message: 'Ошибка сервера' });
    }
  };

  return { upsertCurrent, deleteCurrent };
}
