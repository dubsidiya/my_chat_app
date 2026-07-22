import crypto from 'node:crypto';

import { appEvent, errorEvent } from './auditLog.js';
import {
  getActivePushTokensForUsers,
  getActiveVoipTargetsForUsers,
  pruneInvalidPushTokens,
  pruneInvalidVoipTokens,
} from '../repositories/pushDevicesRepository.js';
import { getAPNsVoipProvider } from '../services/push/apnsVoipProvider.js';

/**
 * Отправка push-уведомлений через Firebase Cloud Messaging (FCM).
 * На iOS FCM использует APNs. Требуются переменные окружения:
 *   - Надёжный вариант: FIREBASE_SERVICE_ACCOUNT_PATH=/path/to/serviceAccount.json
 *     или FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
 *   - Или по частям: FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY
 * Если они не заданы, отправка просто не выполняется (без ошибки).
 */

let messaging = null;
let providerOverride = null;

const DEFINITIVE_TOKEN_ERROR_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);
const FCM_MULTICAST_LIMIT = 500;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function stableCallKitUuid(callId, provided) {
  const explicit = String(provided || '').trim().toLowerCase();
  if (UUID_PATTERN.test(explicit)) return explicit;
  const bytes = Buffer.from(
    crypto.createHash('sha256').update(String(callId || '')).digest().subarray(0, 16)
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join('-');
}

async function sendVoipInviteToUser(
  pool,
  userId,
  payload,
  { provider, collapseId } = {}
) {
  const targets = await getActiveVoipTargetsForUsers(pool, [userId]);
  if (targets.length === 0) {
    return {
      attempted: 0,
      successCount: 0,
      failureCount: 0,
      definitiveInvalidTokens: [],
      skipped: 'no_tokens',
    };
  }
  const adapter = provider || getAPNsVoipProvider();
  const result = await adapter.send(targets, payload, { collapseId });
  if (result.definitiveInvalidTokens?.length > 0) {
    await pruneInvalidVoipTokens(pool, result.definitiveInvalidTokens);
  }
  return result;
}

function fcmIncomingTarget(target) {
  // Android remains on FCM. iOS FCM is a fallback only for installations that
  // do not advertise a valid native VoIP token.
  return target.platform !== 'ios' || target.hasVoipToken !== true;
}

async function buildCredential(admin) {
  // 1) JSON строка (удобно хранить в секретах окружения)
  const jsonRaw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (jsonRaw && typeof jsonRaw === 'string' && jsonRaw.trim()) {
    try {
      const obj = JSON.parse(jsonRaw);
      if (obj?.client_email && obj?.private_key) {
        appEvent('firebase_credential_source', { source: 'json' });
        return { credential: admin.default.credential.cert(obj), projectId: obj.project_id || process.env.FIREBASE_PROJECT_ID || null };
      }
      appEvent('firebase_credential_invalid_json', {});
    } catch (e) {
      errorEvent('firebase_credential_invalid_json', e);
    }
  }

  // 2) Путь к файлу JSON (самый простой и наименее капризный способ на ВМ)
  const path = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (path && typeof path === 'string' && path.trim()) {
    try {
      const fs = await import('fs');
      const raw = fs.readFileSync(path, 'utf8');
      const obj = JSON.parse(raw);
      if (obj?.client_email && obj?.private_key) {
        appEvent('firebase_credential_source', { source: 'path' });
        return { credential: admin.default.credential.cert(obj), projectId: obj.project_id || process.env.FIREBASE_PROJECT_ID || null };
      }
      appEvent('firebase_credential_invalid_path', {});
    } catch (e) {
      errorEvent('firebase_credential_path_error', e);
    }
  }

  // 3) По частям из env
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY;
  if (!projectId || !clientEmail || !privateKey) {
    return null;
  }

  // Sanity-check (не логируем ключ)
  const pk = String(privateKey);
  const hasBegin = pk.includes('BEGIN PRIVATE KEY');
  const hasEnd = pk.includes('END PRIVATE KEY');
  const hasSlashN = pk.includes('\\n');
  const hasRealNl = pk.includes('\n');
  appEvent('firebase_credential_source', { source: 'parts', hasBegin, hasEnd, hasSlashN, hasRealNl, projectId: Boolean(projectId) });

  return {
    credential: admin.default.credential.cert({
      projectId,
      clientEmail,
      privateKey: pk.replace(/\\n/g, '\n'),
    }),
    projectId,
  };
}

async function getMessaging() {
  if (messaging) return messaging;
  try {
    const admin = await import('firebase-admin');
    const built = await buildCredential(admin);
    if (!built?.credential) {
      appEvent('firebase_missing_credentials', {});
      return null;
    }
    if (!admin.default.apps.length) {
      admin.default.initializeApp({
        credential: built.credential,
        ...(built.projectId ? { projectId: built.projectId } : {}),
      });
      appEvent('firebase_initialized', {});
    }
    // Проверяем, что можем получить access token (иначе FCM даст "missing auth credential")
    try {
      const cred = admin.default.app().options?.credential;
      if (cred && typeof cred.getAccessToken === 'function') {
        const tok = await cred.getAccessToken();
        const accessToken = tok?.access_token;
        if (!accessToken || typeof accessToken !== 'string' || accessToken.length < 50) {
          errorEvent('firebase_access_token_invalid', null, {
            hasToken: Boolean(accessToken),
            tokenLength: typeof accessToken === 'string' ? accessToken.length : null,
            expiresIn: tok?.expires_in ?? null,
          });
          return null;
        }
        appEvent('firebase_access_token_ok', { tokenLength: accessToken.length, expiresIn: tok?.expires_in ?? null });
      } else {
        appEvent('firebase_credential_no_get_access_token', {});
      }
    } catch (e) {
      errorEvent('firebase_access_token_error', e);
      return null;
    }

    messaging = admin.default.messaging();
    return messaging;
  } catch (e) {
    errorEvent('firebase_init_failed', e);
    return null;
  }
}

export function createFirebasePushProvider(
  messagingGetter = getMessaging
) {
  return {
    async sendMulticast(message) {
      const fcm = await messagingGetter();
      if (!fcm) return null;
      return fcm.sendEachForMulticast(message);
    },
  };
}

export function setPushProviderForTests(provider) {
  providerOverride = provider || null;
}

function stringifyData(data) {
  return Object.fromEntries(
    Object.entries(data || {})
      .filter(([, value]) => value !== undefined && value !== null)
      .map(([key, value]) => [key, String(value)])
  );
}

/**
 * Send one multicast batch. The provider is injectable so unit tests never
 * need Firebase credentials or network access.
 */
export async function sendPushToTokens(
  tokens,
  title,
  body,
  data = {},
  options = {}
) {
  const cleaned = [...new Set(
    (Array.isArray(tokens) ? tokens : [])
      .filter((token) => typeof token === 'string')
      .map((token) => token.trim())
      .filter(Boolean)
  )];
  if (cleaned.length === 0) {
    return {
      attempted: 0,
      successCount: 0,
      failureCount: 0,
      definitiveInvalidTokens: [],
      skipped: 'no_tokens',
    };
  }

  const provider =
    options.provider || providerOverride || createFirebasePushProvider();
  const messageBase = {
    ...(options.notification === false
      ? {}
      : { notification: { title: String(title || ''), body: String(body || '') } }),
    data: stringifyData(data),
    android: options.android || { priority: 'high' },
    apns:
      options.apns || { payload: { aps: { sound: 'default' } } },
  };

  const summary = {
    attempted: 0,
    successCount: 0,
    failureCount: 0,
    definitiveInvalidTokens: [],
    skipped: null,
  };
  for (let offset = 0; offset < cleaned.length; offset += FCM_MULTICAST_LIMIT) {
    const batch = cleaned.slice(offset, offset + FCM_MULTICAST_LIMIT);
    try {
      const result = await provider.sendMulticast({
        ...messageBase,
        tokens: batch,
      });
      if (!result) {
        if (summary.attempted === 0) {
          return {
            ...summary,
            skipped: 'provider_unavailable',
          };
        }
        summary.skipped = 'provider_unavailable';
        break;
      }
      summary.attempted += batch.length;
      summary.successCount += result.successCount || 0;
      summary.failureCount += result.failureCount || 0;
      for (let index = 0; index < (result.responses || []).length; index++) {
        const response = result.responses[index];
        if (response?.success) continue;
        const code = response?.error?.code || null;
        if (DEFINITIVE_TOKEN_ERROR_CODES.has(code)) {
          summary.definitiveInvalidTokens.push(batch[index]);
        }
        // Never log a provider token or provider error text (some SDK errors
        // embed the registration token).
        appEvent('fcm_token_failure', {
          index: offset + index,
          code,
          definitive: DEFINITIVE_TOKEN_ERROR_CODES.has(code),
        });
      }
    } catch (error) {
      summary.attempted += batch.length;
      summary.failureCount += batch.length;
      summary.skipped = 'provider_error';
      errorEvent(
        'fcm_send_error',
        new Error(error?.code || error?.name || 'provider_error'),
        { tokenCount: batch.length }
      );
    }
  }
  appEvent('fcm_push_result', {
    successCount: summary.successCount,
    failureCount: summary.failureCount,
    total: cleaned.length,
    batches: Math.ceil(cleaned.length / FCM_MULTICAST_LIMIT),
  });
  return summary;
}

export async function sendPushToUsers(
  pool,
  userIds,
  title,
  body,
  data = {},
  options = {}
) {
  const targets = await getActivePushTokensForUsers(pool, userIds);
  const selectedTargets =
    typeof options.targetFilter === 'function'
      ? targets.filter(options.targetFilter)
      : targets;
  const result = await sendPushToTokens(
    selectedTargets.map((target) => target.token),
    title,
    body,
    data,
    options
  );
  if (result.definitiveInvalidTokens.length > 0) {
    await pruneInvalidPushTokens(pool, result.definitiveInvalidTokens);
  }
  return {
    ...result,
    targetCount: selectedTargets.length,
    deviceTargetCount: selectedTargets.filter((target) => target.source === 'device')
      .length,
    legacyTargetCount: selectedTargets.filter((target) => target.source === 'legacy')
      .length,
  };
}

export function callNotificationTag(callId) {
  const digest = crypto
    .createHash('sha256')
    .update(String(callId || 'unknown'))
    .digest('base64url')
    .slice(0, 40);
  return `call_${digest}`;
}

function parseExpiry(expiresAt, fallbackMs) {
  if (expiresAt instanceof Date && Number.isFinite(expiresAt.getTime())) {
    return expiresAt.getTime();
  }
  if (typeof expiresAt === 'number' && Number.isFinite(expiresAt)) {
    return expiresAt;
  }
  const parsed = Date.parse(String(expiresAt || ''));
  return Number.isFinite(parsed) ? parsed : fallbackMs;
}

/**
 * Normal (non-PushKit) incoming-call push. Existing camelCase payload fields
 * remain intact for old clients; timing and notification identity are additive.
 */
export async function sendIncomingCallPushToUser(
  pool,
  calleeUserId,
  payload,
  options = {}
) {
  const {
    callId,
    chatId,
    chatName,
    fromUserId,
    fromEmail,
    mediaType,
    isGroup,
    expiresAt,
    callKitUuid,
  } = payload;
  if (!callId || !chatId || !fromUserId) return null;

  const sentAtMs = Date.now();
  const expiresAtMs = parseExpiry(expiresAt, sentAtMs + 75_000);
  const ttlMs = Math.floor(expiresAtMs - sentAtMs);
  if (ttlMs <= 0) {
    appEvent('incoming_call_push_skipped', {
      reason: 'already_expired',
      callId: String(callId),
    });
    return {
      attempted: 0,
      successCount: 0,
      failureCount: 0,
      targetCount: 0,
      definitiveInvalidTokens: [],
      skipped: 'already_expired',
    };
  }

  try {
    const isVideo = String(mediaType || 'audio').toLowerCase() === 'video';
    const group = Boolean(isGroup);
    const callerLabel = (fromEmail || chatName || 'Пользователь')
      .toString()
      .slice(0, 80);
    const title = group
      ? 'Групповой звонок'
      : isVideo
        ? 'Входящий видеозвонок'
        : 'Входящий звонок';
    const body = group
      ? `${callerLabel} начинает звонок в «${(chatName || 'группе').toString().slice(0, 40)}»`
      : isVideo
        ? `${callerLabel} звонит с видео`
        : `${callerLabel} звонит`;
    const notificationTag = callNotificationTag(callId);
    const resolvedCallKitUuid = stableCallKitUuid(callId, callKitUuid);
    const expiresAtIso = new Date(expiresAtMs).toISOString();
    const sentAtIso = new Date(sentAtMs).toISOString();

    const data = {
      type: group ? 'incoming_group_call' : 'incoming_call',
      callId: String(callId),
      callKitUuid: resolvedCallKitUuid,
      callkit_uuid: resolvedCallKitUuid,
      chatId: String(chatId),
      chatName: (chatName || callerLabel).toString().slice(0, 120),
      fromUserId: String(fromUserId),
      fromEmail: callerLabel,
      isGroup: group ? '1' : '0',
      mediaType: isVideo ? 'video' : 'audio',
      expiresAt: expiresAtIso,
      expires_at: expiresAtIso,
      sentAt: sentAtIso,
      sent_at: sentAtIso,
      notificationId: '0',
      notificationTag,
      collapseKey: notificationTag,
    };

    let voipResult;
    try {
      voipResult = await sendVoipInviteToUser(
        pool,
        calleeUserId,
        {
          type: group ? 'incoming_group_call' : 'incoming_call',
          callId: String(callId),
          callKitUuid: resolvedCallKitUuid,
          chatId: String(chatId),
          chatName: (chatName || callerLabel).toString().slice(0, 120),
          fromUserId: String(fromUserId),
          fromLabel: callerLabel,
          isGroup: group,
          mediaType: isVideo ? 'video' : 'audio',
          expiresAt: expiresAtIso,
          sentAt: sentAtIso,
        },
        {
          provider: options.apnsVoipProvider,
          collapseId: notificationTag,
        }
      );
    } catch (error) {
      errorEvent(
        'apns_voip_invite_error',
        new Error(error?.code || error?.name || 'provider_error'),
        { callId: String(callId), targetKind: group ? 'group' : 'direct' }
      );
      voipResult = {
        attempted: 0,
        successCount: 0,
        failureCount: 0,
        definitiveInvalidTokens: [],
        skipped: 'provider_error',
      };
    }

    const fcmResult = await sendPushToUsers(
      pool,
      [calleeUserId],
      title,
      body,
      data,
      {
        provider: options.provider,
        targetFilter: (target) =>
          fcmIncomingTarget(target) &&
          (typeof options.targetFilter !== 'function' ||
            options.targetFilter(target)),
        android: {
          priority: 'high',
          ttl: ttlMs,
          collapseKey: notificationTag,
          notification: {
            channelId: 'voice_calls',
            priority: 'max',
            defaultSound: true,
            visibility: 'public',
            tag: notificationTag,
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert',
            'apns-expiration': String(Math.floor(expiresAtMs / 1000)),
            'apns-collapse-id': notificationTag,
          },
          payload: {
            aps: {
              sound: 'default',
              'content-available': 1,
            },
          },
        },
      }
    );
    appEvent('incoming_call_push_result', {
      callId: String(callId),
      chatId: String(chatId),
      successCount: fcmResult.successCount + (voipResult.successCount || 0),
      failureCount: fcmResult.failureCount + (voipResult.failureCount || 0),
      targetCount: fcmResult.targetCount + (voipResult.attempted || 0),
    });
    return {
      ...fcmResult,
      successCount: fcmResult.successCount + (voipResult.successCount || 0),
      failureCount: fcmResult.failureCount + (voipResult.failureCount || 0),
      targetCount: fcmResult.targetCount + (voipResult.attempted || 0),
      voipTargetCount: voipResult.attempted || 0,
      voip: voipResult,
    };
  } catch (error) {
    errorEvent(
      'incoming_call_push_error',
      new Error(error?.code || error?.name || 'push_error'),
      { callId: String(callId), chatId: String(chatId) }
    );
    return null;
  }
}

/**
 * LiveKit group invitation. Credentials, room names and participant tokens are
 * intentionally not accepted by this API and therefore cannot leak to FCM.
 */
export async function sendLiveKitGroupCallPushToUser(
  pool,
  userId,
  {
    callId,
    chatId,
    chatName,
    fromUserId,
    fromLabel,
    mediaType,
    expiresAt,
    callKitUuid,
  },
  options = {}
) {
  if (!callId || !chatId || !fromUserId) return null;
  const sentAtMs = Date.now();
  const expiresAtMs = parseExpiry(expiresAt, sentAtMs + 75_000);
  const ttlMs = Math.floor(expiresAtMs - sentAtMs);
  if (ttlMs <= 0) {
    return {
      attempted: 0,
      successCount: 0,
      failureCount: 0,
      targetCount: 0,
      definitiveInvalidTokens: [],
      skipped: 'already_expired',
    };
  }

  const isVideo = String(mediaType || 'audio').toLowerCase() === 'video';
  const label = String(fromLabel || chatName || 'Участник').slice(0, 80);
  const safeChatName = String(chatName || 'Группа').slice(0, 120);
  const notificationTag = callNotificationTag(callId);
  const resolvedCallKitUuid = stableCallKitUuid(callId, callKitUuid);
  const expiresAtIso = new Date(expiresAtMs).toISOString();
  const data = {
    type: 'incoming_livekit_group_call',
    provider: 'livekit',
    protocolVersion: '2',
    callId: String(callId),
    callKitUuid: resolvedCallKitUuid,
    callkit_uuid: resolvedCallKitUuid,
    chatId: String(chatId),
    chatName: safeChatName,
    fromUserId: String(fromUserId),
    fromLabel: label,
    isGroup: '1',
    initialMediaType: isVideo ? 'video' : 'audio',
    mediaType: isVideo ? 'video' : 'audio',
    expiresAt: expiresAtIso,
    expires_at: expiresAtIso,
    sentAt: new Date(sentAtMs).toISOString(),
    notificationId: '0',
    notificationTag,
    collapseKey: notificationTag,
  };
  let voipResult;
  try {
    voipResult = await sendVoipInviteToUser(
      pool,
      userId,
      {
        type: 'incoming_livekit_group_call',
        provider: 'livekit',
        protocolVersion: '2',
        callId: String(callId),
        callKitUuid: resolvedCallKitUuid,
        chatId: String(chatId),
        chatName: safeChatName,
        fromUserId: String(fromUserId),
        fromLabel: label,
        isGroup: true,
        mediaType: isVideo ? 'video' : 'audio',
        expiresAt: expiresAtIso,
        sentAt: new Date(sentAtMs).toISOString(),
      },
      {
        provider: options.apnsVoipProvider,
        collapseId: notificationTag,
      }
    );
  } catch (error) {
    errorEvent(
      'apns_voip_invite_error',
      new Error(error?.code || error?.name || 'provider_error'),
      { callId: String(callId), targetKind: 'livekit_group' }
    );
    voipResult = {
      attempted: 0,
      successCount: 0,
      failureCount: 0,
      definitiveInvalidTokens: [],
      skipped: 'provider_error',
    };
  }
  const fcmResult = await sendPushToUsers(
    pool,
    [userId],
    isVideo ? 'Групповой видеозвонок' : 'Групповой звонок',
    `${label} начинает звонок в «${safeChatName.slice(0, 40)}»`,
    data,
    {
      provider: options.provider,
      targetFilter: (target) =>
        fcmIncomingTarget(target) &&
        (typeof options.targetFilter === 'function'
          ? options.targetFilter(target)
          : target.source === 'device' &&
            Number(target.capabilities?.livekitGroupProtocolVersion || 0) >= 2),
      android: {
        priority: 'high',
        ttl: ttlMs,
        collapseKey: notificationTag,
        notification: {
          channelId: 'voice_calls',
          priority: 'max',
          defaultSound: true,
          visibility: 'public',
          tag: notificationTag,
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-push-type': 'alert',
          'apns-expiration': String(Math.floor(expiresAtMs / 1000)),
          'apns-collapse-id': notificationTag,
        },
        payload: {
          aps: { sound: 'default', 'content-available': 1 },
        },
      },
    }
  );
  return {
    ...fcmResult,
    successCount: fcmResult.successCount + (voipResult.successCount || 0),
    failureCount: fcmResult.failureCount + (voipResult.failureCount || 0),
    targetCount: fcmResult.targetCount + (voipResult.attempted || 0),
    voipTargetCount: voipResult.attempted || 0,
    voip: voipResult,
  };
}

/**
 * Best-effort cancellation/reconciliation for other installations of the same
 * account. Always a normal FCM/APNs background push — PushKit/VoIP is reserved
 * strictly for new incoming invites (Apple policy).
 */
export async function sendCallReconciliationPushToUser(
  pool,
  userId,
  {
    callId,
    callKitUuid,
    chatId,
    status = 'accepted',
    reason = 'answered_elsewhere',
  },
  options = {}
) {
  if (!callId || !userId) return null;
  const sentAtMs = Date.now();
  const expiresAtMs = sentAtMs + 60_000;
  const notificationTag = callNotificationTag(callId);
  return sendPushToUsers(
    pool,
    [userId],
    null,
    null,
    {
      type: 'call_reconcile',
      callId: String(callId),
      callKitUuid: stableCallKitUuid(callId, callKitUuid),
      chatId: chatId == null ? '' : String(chatId),
      status,
      reason,
      sentAt: new Date(sentAtMs).toISOString(),
      expiresAt: new Date(expiresAtMs).toISOString(),
      notificationId: '0',
      notificationTag,
      collapseKey: notificationTag,
      silent: '1',
    },
    {
      provider: options.provider,
      notification: false,
      targetFilter: (target) =>
        target.source === 'device' &&
        target.capabilities?.callReconciliation === true,
      android: {
        priority: 'high',
        ttl: expiresAtMs - sentAtMs,
        collapseKey: notificationTag,
      },
      apns: {
        headers: {
          'apns-priority': '5',
          'apns-push-type': 'background',
          'apns-expiration': String(Math.floor(expiresAtMs / 1000)),
          'apns-collapse-id': notificationTag,
        },
        payload: { aps: { 'content-available': 1 } },
      },
    }
  );
}
