#!/usr/bin/env node
/**
 * Smoke: WebSocket call signaling relay (invite → accept → offer → answer → ice).
 * Requires BASE_URL, SMOKE_USER_A_EMAIL/PASSWORD, SMOKE_USER_B_EMAIL/PASSWORD in .env
 * or env vars. Does not test WebRTC media — only server relay.
 */
import 'dotenv/config';
import WebSocket from 'ws';

const BASE = (process.env.BASE_URL || process.env.API_BASE_URL || 'http://localhost:3000').replace(/\/$/, '');
const WS_BASE = BASE.replace(/^http/, 'ws');

async function login(email, password) {
  const res = await fetch(`${BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) {
    throw new Error(`login failed ${email}: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  return { token: data.token, userId: String(data.user?.id ?? data.id) };
}

function connectWs(token) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(WS_BASE, { headers: { Authorization: `Bearer ${token}` } });
    const timeout = setTimeout(() => reject(new Error('WS connect timeout')), 15000);
    ws.on('open', () => {
      clearTimeout(timeout);
      resolve(ws);
    });
    ws.on('error', (e) => {
      clearTimeout(timeout);
      reject(e);
    });
  });
}

function waitForType(ws, type, timeoutMs = 15000) {
  return new Promise((resolve, reject) => {
    const onMessage = (raw) => {
      try {
        const msg = JSON.parse(raw.toString());
        if (msg.type === type) {
          clearTimeout(timer);
          ws.off('message', onMessage);
          resolve(msg);
        }
      } catch (_) {}
    };
    const timer = setTimeout(() => {
      ws.off('message', onMessage);
      reject(new Error(`timeout waiting for ${type}`));
    }, timeoutMs);
    ws.on('message', onMessage);
  });
}

function send(ws, payload) {
  ws.send(JSON.stringify(payload));
}

async function findDmChat(tokenA, tokenB, userIdA, userIdB) {
  const res = await fetch(`${BASE}/chats`, {
    headers: { Authorization: `Bearer ${tokenA}` },
  });
  if (!res.ok) throw new Error(`chats list failed: ${res.status}`);
  const chats = await res.json();
  for (const c of chats) {
    if (c.is_group) continue;
    const other = String(c.other_user_id ?? c.otherUserId ?? '');
    if (other === userIdB) return String(c.id);
  }
  const createRes = await fetch(`${BASE}/chats`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${tokenA}`,
    },
    body: JSON.stringify({ user_id: userIdB }),
  });
  if (!createRes.ok) {
    throw new Error(`create chat failed: ${createRes.status} ${await createRes.text()}`);
  }
  const created = await createRes.json();
  return String(created.id ?? created.chat_id);
}

async function scenarioHappyPath(wsA, wsB, chatId) {
  const callId = `smoke-happy-${Date.now()}`;
  const inviteWait = waitForType(wsB, 'call_invite');
  send(wsA, { type: 'call_invite', call_id: callId, chat_id: chatId });
  const invite = await inviteWait;
  if (invite.call_id !== callId) throw new Error('invite call_id mismatch');

  const acceptWait = waitForType(wsA, 'call_accept');
  send(wsB, { type: 'call_accept', call_id: callId, chat_id: chatId });
  await acceptWait;

  const fakeOffer = {
    type: 'offer',
    sdp: 'v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n',
  };
  const offerWait = waitForType(wsB, 'call_offer');
  send(wsA, { type: 'call_offer', call_id: callId, chat_id: chatId, sdp: fakeOffer });
  const offer = await offerWait;
  if (!offer.sdp?.type) throw new Error('offer relay missing sdp');

  const fakeAnswer = { type: 'answer', sdp: fakeOffer.sdp };
  const answerWait = waitForType(wsA, 'call_answer');
  send(wsB, { type: 'call_answer', call_id: callId, chat_id: chatId, sdp: fakeAnswer });
  await answerWait;

  const iceWait = waitForType(wsB, 'call_ice');
  send(wsA, {
    type: 'call_ice',
    call_id: callId,
    chat_id: chatId,
    candidate: { candidate: 'candidate:1 1 udp 1 1.1.1.1 12345 typ host', sdpMid: '0', sdpMLineIndex: 0 },
  });
  await iceWait;

  const hangupWait = waitForType(wsB, 'call_hangup');
  send(wsA, { type: 'call_hangup', call_id: callId, chat_id: chatId });
  await hangupWait;
}

async function scenarioReject(wsA, wsB, chatId) {
  const callId = `smoke-reject-${Date.now()}`;
  const inviteWait = waitForType(wsB, 'call_invite');
  send(wsA, { type: 'call_invite', call_id: callId, chat_id: chatId });
  await inviteWait;

  const rejectWait = waitForType(wsA, 'call_reject');
  send(wsB, {
    type: 'call_reject',
    call_id: callId,
    chat_id: chatId,
    reason: 'declined',
  });
  const reject = await rejectWait;
  if (reject.reason !== 'declined') {
    throw new Error(`reject reason mismatch: ${reject.reason}`);
  }
}

async function scenarioBusy(wsA, wsB, chatId) {
  // A→B уже ringing, второй invite от A с другим callId должен получить call_error{busy}.
  const firstCallId = `smoke-busy-1-${Date.now()}`;
  const firstInviteWait = waitForType(wsB, 'call_invite');
  send(wsA, { type: 'call_invite', call_id: firstCallId, chat_id: chatId });
  await firstInviteWait;

  const secondCallId = `smoke-busy-2-${Date.now()}`;
  const errorWait = waitForType(wsA, 'call_error');
  send(wsA, { type: 'call_invite', call_id: secondCallId, chat_id: chatId });
  const err = await errorWait;
  if (err.code !== 'busy') {
    throw new Error(`expected call_error{busy}, got ${JSON.stringify(err)}`);
  }

  // Прибираем за собой.
  const hangupWait = waitForType(wsB, 'call_hangup');
  send(wsA, { type: 'call_hangup', call_id: firstCallId, chat_id: chatId });
  await hangupWait;
}

async function main() {
  const emailA = process.env.SMOKE_USER_A_EMAIL || process.env.SMOKE_EMAIL;
  const passA = process.env.SMOKE_USER_A_PASSWORD || process.env.SMOKE_PASSWORD;
  const emailB = process.env.SMOKE_USER_B_EMAIL;
  const passB = process.env.SMOKE_USER_B_PASSWORD;

  if (!emailA || !passA || !emailB || !passB) {
    console.error('Set SMOKE_USER_A_EMAIL, SMOKE_USER_A_PASSWORD, SMOKE_USER_B_EMAIL, SMOKE_USER_B_PASSWORD');
    process.exit(1);
  }

  const userA = await login(emailA, passA);
  const userB = await login(emailB, passB);
  const chatId = await findDmChat(userA.token, userB.token, userA.userId, userB.userId);

  const wsA = await connectWs(userA.token);
  const wsB = await connectWs(userB.token);

  try {
    await scenarioHappyPath(wsA, wsB, chatId);
    console.log('smoke-call-signaling[happy]: OK (invite/accept/offer/answer/ice/hangup)');

    await scenarioReject(wsA, wsB, chatId);
    console.log('smoke-call-signaling[reject]: OK (invite/reject relayed)');

    await scenarioBusy(wsA, wsB, chatId);
    console.log('smoke-call-signaling[busy]: OK (second invite → call_error{busy})');
  } finally {
    wsA.close();
    wsB.close();
  }

  console.log('smoke-call-signaling: ALL OK');
}

main().catch((e) => {
  console.error('smoke-call-signaling: FAIL', e.message || e);
  process.exit(1);
});
