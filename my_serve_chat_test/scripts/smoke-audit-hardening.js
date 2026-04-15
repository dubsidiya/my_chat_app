/**
 * Hardening smoke checks:
 * 1) sendMessage idempotency (same key => same response, no duplicate insert)
 * 2) report slots fail-fast for invalid makeup origin
 * 3) websocket auth via subprotocol auth.<token>
 *
 * Run:
 *   node scripts/smoke-audit-hardening.js
 */
import http from 'http';
import WebSocket from 'ws';
import pool from '../db.js';
import { sendMessage } from '../controllers/messagesController.js';
import { createReport } from '../controllers/reportsController.js';
import { generateToken } from '../middleware/auth.js';
import { setupWebSocket } from '../websocket/websocket.js';
import { getDateInTimeZoneISO, getUserTimeZone } from '../utils/timezone.js';

const makeRes = () => ({
  statusCode: 200,
  body: null,
  status(code) {
    this.statusCode = code;
    return this;
  },
  json(payload) {
    this.body = payload;
    return this;
  },
  send(payload) {
    this.body = payload;
    return this;
  },
});

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

const addDays = (isoDate, delta) => {
  const d = new Date(`${isoDate}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
};

const pickFreeReportDate = async (teacherId) => {
  const client = await pool.connect();
  try {
    const tz = await getUserTimeZone(client, teacherId);
    const today = getDateInTimeZoneISO(tz);
    for (let i = 0; i < 30; i++) {
      const candidate = addDays(today, -i);
      const exists = await client.query(
        'SELECT 1 FROM reports WHERE created_by = $1 AND report_date = $2 LIMIT 1',
        [teacherId, candidate]
      );
      if (exists.rowCount === 0) return candidate;
    }
    throw new Error('Не удалось найти свободную дату отчёта для smoke-теста');
  } finally {
    client.release();
  }
};

const testSendMessageIdempotency = async () => {
  const seed = await pool.query(
    `SELECT cu.chat_id, cu.user_id, u.email
     FROM chat_users cu
     JOIN users u ON u.id = cu.user_id
     ORDER BY cu.chat_id DESC, cu.user_id DESC
     LIMIT 1`
  );
  assert(seed.rowCount > 0, 'Нет данных chat_users для sendMessage smoke');
  const { chat_id: chatId, user_id: userId, email } = seed.rows[0];

  const uniqueSuffix = `${Date.now()}-${Math.floor(Math.random() * 100000)}`;
  const idemKey = `smoke-send-idem-${uniqueSuffix}`;
  const payload = `smoke idempotent message ${uniqueSuffix}`;

  const reqBase = {
    user: { userId, email },
    body: {
      chat_id: String(chatId),
      content: payload,
    },
    headers: {
      'idempotency-key': idemKey,
    },
  };

  const res1 = makeRes();
  await sendMessage(
    {
      ...reqBase,
      body: { ...reqBase.body },
      headers: { ...reqBase.headers },
    },
    res1
  );
  assert(res1.statusCode === 201, `sendMessage #1 статус ${res1.statusCode}`);
  assert(res1.body?.id, 'sendMessage #1 не вернул message.id');

  const res2 = makeRes();
  await sendMessage(
    {
      ...reqBase,
      body: { ...reqBase.body },
      headers: { ...reqBase.headers },
    },
    res2
  );
  assert(res2.statusCode === 201, `sendMessage #2 статус ${res2.statusCode}`);
  assert(
    Number(res2.body?.id) === Number(res1.body?.id),
    'sendMessage replay вернул другой message.id'
  );

  const messageId = Number(res1.body.id);
  const count = await pool.query(
    'SELECT COUNT(*)::int AS c FROM messages WHERE id = $1',
    [messageId]
  );
  assert((count.rows[0]?.c ?? 0) === 1, 'Обнаружен дубль insert для idempotent sendMessage');

  await pool.query('DELETE FROM messages WHERE id = $1', [messageId]);
  await pool.query(
    `DELETE FROM idempotency_keys
     WHERE user_id = $1 AND scope = 'messages:send' AND idempotency_key = $2`,
    [userId, idemKey]
  );
};

const testReportSlotsFailFast = async () => {
  const seed = await pool.query(
    `SELECT ts.teacher_id, ts.student_id
     FROM teacher_students ts
     ORDER BY ts.created_at DESC
     LIMIT 1`
  );
  assert(seed.rowCount > 0, 'Нет teacher_students для report fail-fast smoke');
  const teacherId = seed.rows[0].teacher_id;
  const studentId = seed.rows[0].student_id;
  const reportDate = await pickFreeReportDate(teacherId);
  const maxLesson = await pool.query('SELECT COALESCE(MAX(id), 0)::int AS max_id FROM lessons');
  const missingOriginId = (maxLesson.rows[0]?.max_id ?? 0) + 100000;

  const beforeCountRes = await pool.query(
    'SELECT COUNT(*)::int AS c FROM reports WHERE created_by = $1 AND report_date = $2',
    [teacherId, reportDate]
  );
  const beforeCount = beforeCountRes.rows[0]?.c ?? 0;

  const req = {
    user: { userId: teacherId },
    body: {
      report_date: reportDate,
      slots: [
        {
          timeStart: '12:00',
          timeEnd: '13:00',
          students: [
            {
              studentId: Number(studentId),
              price: 1500,
              status: 'makeup',
              originLessonId: missingOriginId,
            },
          ],
        },
      ],
    },
    headers: {
      'idempotency-key': `smoke-report-failfast-${Date.now()}`,
    },
  };
  const res = makeRes();
  await createReport(req, res);
  assert(res.statusCode === 400, `createReport invalid makeup slots должен вернуть 400, получили ${res.statusCode}`);

  const afterCountRes = await pool.query(
    'SELECT COUNT(*)::int AS c FROM reports WHERE created_by = $1 AND report_date = $2',
    [teacherId, reportDate]
  );
  const afterCount = afterCountRes.rows[0]?.c ?? 0;
  assert(afterCount === beforeCount, 'Отчёт не должен создаваться при invalid makeup origin в slots');
};

const wsOpenWithTimeout = (socket, timeoutMs = 6000) =>
  new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WS connect timeout')), timeoutMs);
    socket.once('open', () => {
      clearTimeout(timer);
      resolve();
    });
    socket.once('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
    socket.once('close', (code, reason) => {
      clearTimeout(timer);
      reject(new Error(`WS closed before open: code=${code} reason=${String(reason)}`));
    });
  });

const testWebSocketSubprotocolAuth = async () => {
  const seed = await pool.query(
    `SELECT id, email, COALESCE(token_version, 0) AS token_version
     FROM users
     ORDER BY id DESC
     LIMIT 1`
  );
  assert(seed.rowCount > 0, 'Нет users для websocket auth smoke');
  const user = seed.rows[0];
  const token = generateToken(user.id, user.email, false, user.token_version ?? 0);

  const httpServer = http.createServer((req, res) => {
    res.statusCode = 200;
    res.end('ok');
  });
  setupWebSocket(httpServer);

  await new Promise((resolve, reject) => {
    httpServer.listen(0, '127.0.0.1', (err) => {
      if (err) reject(err);
      else resolve();
    });
  });

  const addr = httpServer.address();
  assert(addr && typeof addr === 'object' && addr.port, 'Не удалось получить порт тестового ws-сервера');
  const wsUrl = `ws://127.0.0.1:${addr.port}`;
  const client = new WebSocket(wsUrl, [`auth.${token}`]);

  try {
    await wsOpenWithTimeout(client, 6000);
  } finally {
    try { client.close(); } catch (_) {}
    await new Promise((resolve) => httpServer.close(() => resolve()));
  }
};

const run = async () => {
  await testSendMessageIdempotency();
  await testReportSlotsFailFast();
  await testWebSocketSubprotocolAuth();
  console.log('✅ smoke-audit-hardening: ok');
  await pool.end();
  process.exit(0);
};

run().catch(async (error) => {
  console.error('❌ smoke-audit-hardening failed:', error?.message || error);
  try { await pool.end(); } catch (_) {}
  process.exit(1);
});

