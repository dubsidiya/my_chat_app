#!/usr/bin/env node
/**
 * Smoke: group voice call signaling (create → invite → join → offer/answer/ice → leave).
 * Requires BASE_URL + SMOKE_USER_A/B credentials. Optional SMOKE_USER_C for non-member check.
 * Does not test WebRTC media — only server relay.
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

async function findOrCreateGroup(tokenA, userIdB) {
  const res = await fetch(`${BASE}/chats`, {
    headers: { Authorization: `Bearer ${tokenA}` },
  });
  if (!res.ok) throw new Error(`chats list failed: ${res.status}`);
  const chats = await res.json();
  for (const c of chats) {
    if (!c.is_group) continue;
    return String(c.id);
  }

  const attempts = [
    {
      url: `${BASE}/chats`,
      body: { name: `smoke-group-${Date.now()}`, is_group: true, userIds: [userIdB] },
    },
    {
      url: `${BASE}/chats`,
      body: { name: `smoke-group-${Date.now()}`, is_group: true, user_ids: [userIdB] },
    },
  ];

  let lastErr = '';
  for (const attempt of attempts) {
    const createRes = await fetch(attempt.url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${tokenA}`,
      },
      body: JSON.stringify(attempt.body),
    });
    if (createRes.ok) {
      const created = await createRes.json();
      return String(created.id ?? created.chat_id);
    }
    lastErr = `${createRes.status} ${await createRes.text()}`;
  }
  throw new Error(`create group failed: ${lastErr}`);
}

async function scenarioHappy(wsA, wsB, chatId, userIdA, userIdB) {
  const callId = `smoke-gcall-${Date.now()}`;
  const createdWait = waitForType(wsA, 'gcall_created');
  const inviteWait = waitForType(wsB, 'gcall_invite');
  send(wsA, { type: 'gcall_create', call_id: callId, chat_id: chatId });
  await createdWait;
  const invite = await inviteWait;
  if (invite.call_id !== callId) throw new Error('invite call_id mismatch');

  const joinedWait = waitForType(wsB, 'gcall_joined');
  const peerJoinedWait = waitForType(wsA, 'gcall_peer_joined');
  send(wsB, { type: 'gcall_join', call_id: callId, chat_id: chatId });
  await joinedWait;
  await peerJoinedWait;

  const fakeOffer = {
    type: 'offer',
    sdp: 'v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n',
  };
  const offerWait = waitForType(wsB, 'gcall_offer');
  send(wsA, {
    type: 'gcall_offer',
    call_id: callId,
    chat_id: chatId,
    to_user_id: userIdB,
    sdp: fakeOffer,
  });
  const offer = await offerWait;
  if (!offer.sdp?.type) throw new Error('gcall_offer missing sdp');

  const fakeAnswer = { type: 'answer', sdp: fakeOffer.sdp };
  const answerWait = waitForType(wsA, 'gcall_answer');
  send(wsB, {
    type: 'gcall_answer',
    call_id: callId,
    chat_id: chatId,
    to_user_id: userIdA,
    sdp: fakeAnswer,
  });
  await answerWait;

  const iceWait = waitForType(wsB, 'gcall_ice');
  send(wsA, {
    type: 'gcall_ice',
    call_id: callId,
    chat_id: chatId,
    to_user_id: userIdB,
    candidate: {
      candidate: 'candidate:1 1 udp 1 1.1.1.1 12345 typ host',
      sdpMid: '0',
      sdpMLineIndex: 0,
    },
  });
  await iceWait;

  const leftWait = waitForType(wsA, 'gcall_peer_left');
  send(wsB, { type: 'gcall_leave', call_id: callId, chat_id: chatId });
  await leftWait;

  const endedWait = waitForType(wsB, 'gcall_ended');
  send(wsA, { type: 'gcall_leave', call_id: callId, chat_id: chatId });
  await endedWait;
}

async function scenarioReject(wsA, wsB, chatId) {
  const callId = `smoke-gcall-reject-${Date.now()}`;
  const inviteWait = waitForType(wsB, 'gcall_invite');
  send(wsA, { type: 'gcall_create', call_id: callId, chat_id: chatId });
  await inviteWait;

  send(wsB, {
    type: 'gcall_reject',
    call_id: callId,
    chat_id: chatId,
    reason: 'declined',
  });
  send(wsA, { type: 'gcall_leave', call_id: callId, chat_id: chatId });
}

async function scenarioNonMemberForbidden(wsC, chatId) {
  const callId = `smoke-gcall-forbid-${Date.now()}`;
  const errWait = waitForType(wsC, 'gcall_error');
  send(wsC, { type: 'gcall_create', call_id: callId, chat_id: chatId });
  const err = await errWait;
  if (err.code !== 'not_a_member' && err.code !== 'forbidden') {
    throw new Error(`expected not_a_member, got ${JSON.stringify(err)}`);
  }
}

async function main() {
  const emailA = process.env.SMOKE_USER_A_EMAIL || process.env.SMOKE_EMAIL;
  const passA = process.env.SMOKE_USER_A_PASSWORD || process.env.SMOKE_PASSWORD;
  const emailB = process.env.SMOKE_USER_B_EMAIL;
  const passB = process.env.SMOKE_USER_B_PASSWORD;
  const emailC = process.env.SMOKE_USER_C_EMAIL;
  const passC = process.env.SMOKE_USER_C_PASSWORD;

  if (!emailA || !passA || !emailB || !passB) {
    console.error('Set SMOKE_USER_A_EMAIL/PASSWORD and SMOKE_USER_B_EMAIL/PASSWORD');
    process.exit(1);
  }

  const userA = await login(emailA, passA);
  const userB = await login(emailB, passB);
  const chatId = await findOrCreateGroup(userA.token, userB.userId);

  const wsA = await connectWs(userA.token);
  const wsB = await connectWs(userB.token);
  let wsC = null;
  if (emailC && passC) {
    const userC = await login(emailC, passC);
    wsC = await connectWs(userC.token);
  }

  try {
    await scenarioHappy(wsA, wsB, chatId, userA.userId, userB.userId);
    console.log('smoke-group-call[happy]: OK');

    await scenarioReject(wsA, wsB, chatId);
    console.log('smoke-group-call[reject]: OK');

    if (wsC) {
      await scenarioNonMemberForbidden(wsC, chatId);
      console.log('smoke-group-call[forbidden]: OK');
    } else {
      console.log('smoke-group-call[forbidden]: SKIP (no SMOKE_USER_C)');
    }
  } finally {
    wsA.close();
    wsB.close();
    wsC?.close();
  }

  console.log('smoke-group-call: ALL OK');
}

main().catch((e) => {
  console.error('smoke-group-call: FAIL', e.message || e);
  process.exit(1);
});
