/**
 * Отправка push-уведомлений через Firebase Cloud Messaging (FCM).
 * На iOS FCM использует APNs. Требуются переменные окружения:
 *   FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY
 * Если они не заданы, отправка просто не выполняется (без ошибки).
 */

let messaging = null;

async function getMessaging() {
  if (messaging) return messaging;
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY;
  if (!projectId || !clientEmail || !privateKey) {
    return null;
  }
  try {
    const admin = await import('firebase-admin');
    if (!admin.default.apps.length) {
      admin.default.initializeApp({
        credential: admin.default.credential.cert({
          projectId,
          clientEmail,
          privateKey: privateKey.replace(/\\n/g, '\n'),
        }),
      });
    }
    messaging = admin.default.messaging();
    return messaging;
  } catch (e) {
    console.error('Firebase Admin init failed:', e.message);
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
  if (cleaned.length === 0) return;
  const fcm = await getMessaging();
  if (!fcm) {
    if (process.env.NODE_ENV === 'development') {
      console.log('Push skipped: Firebase not configured');
    }
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
    if (process.env.NODE_ENV === 'development' && result.failureCount > 0) {
      console.log('FCM partial failure:', result.failureCount, result.responses);
    }
  } catch (err) {
    console.error('FCM send error:', err.message);
  }
}
