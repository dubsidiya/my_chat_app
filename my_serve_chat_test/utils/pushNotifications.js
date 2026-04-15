import { appEvent, errorEvent } from './auditLog.js';

/**
 * Отправка push-уведомлений через Firebase Cloud Messaging (FCM).
 * На iOS FCM использует APNs. Требуются переменные окружения:
 *   - Надёжный вариант: FIREBASE_SERVICE_ACCOUNT_PATH=/path/to/serviceAccount.json
 *     или FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
 *   - Или по частям: FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY
 * Если они не заданы, отправка просто не выполняется (без ошибки).
 */

let messaging = null;

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

/**
 * Отправить push указанным FCM-токенам.
 * @param {string[]} tokens - массив FCM-токенов
 * @param {string} title - заголовок уведомления
 * @param {string} body - текст
 * @param {object} data - произвольные данные (например chatId для перехода в чат)
 */
export async function sendPushToTokens(tokens, title, body, data = {}) {
  const cleaned = tokens.filter(Boolean);
  if (cleaned.length === 0) {
    if (process.env.NODE_ENV === 'development') console.log('Push skipped: no FCM tokens');
    return;
  }
  const fcm = await getMessaging();
  if (!fcm) {
    console.warn('Push skipped: Firebase not configured (check FIREBASE_* env vars on server)');
    return;
  }
  try {
    const message = {
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
      tokens: cleaned,
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    };
    const result = await fcm.sendEachForMulticast(message);
    appEvent('fcm_push_result', { successCount: result.successCount, failureCount: result.failureCount, total: cleaned.length });
    if (result.failureCount > 0 && result.responses) {
      result.responses.forEach((r, i) => {
        if (!r.success) {
          const err = r.error;
          appEvent('fcm_token_failure', {
            index: i,
            code: err?.code || null,
            message: err?.message || String(err),
            // FirebaseMessagingError иногда содержит errorInfo (без секретов)
            errorInfo: err?.errorInfo || null,
            cause: err?.cause ? (err.cause.message || String(err.cause)) : null,
          });
        }
      });
    }
  } catch (err) {
    errorEvent('fcm_send_error', err);
  }
}
