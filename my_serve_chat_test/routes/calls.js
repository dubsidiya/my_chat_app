import express from 'express';
import { authenticateToken } from '../middleware/auth.js';

const router = express.Router();

function parseIceServersFromEnv() {
  const servers = [];

  const stunRaw = process.env.WEBRTC_STUN_URLS || 'stun:stun.l.google.com:19302';
  for (const url of stunRaw.split(',').map((s) => s.trim()).filter(Boolean)) {
    servers.push({ urls: url });
  }

  const turnUrlRaw = (process.env.WEBRTC_TURN_URL || '').trim();
  const turnUser = (process.env.WEBRTC_TURN_USERNAME || '').trim();
  const turnCred = (process.env.WEBRTC_TURN_CREDENTIAL || '').trim();
  if (turnUrlRaw && turnUser && turnCred) {
    const turnUrls = new Set(
      turnUrlRaw
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
    );
    // TCP fallback helps on strict mobile NAT / firewalls.
    for (const url of [...turnUrls]) {
      if (url.startsWith('turn:') && !url.includes('transport=tcp')) {
        turnUrls.add(url.includes('?') ? `${url}&transport=tcp` : `${url}?transport=tcp`);
      }
    }
    servers.push({
      urls: [...turnUrls],
      username: turnUser,
      credential: turnCred,
    });
  }

  return servers;
}

/** GET /calls/ice-servers — STUN/TURN for WebRTC (auth required). */
router.get('/ice-servers', authenticateToken, (req, res) => {
  res.json({ iceServers: parseIceServersFromEnv() });
});

export default router;
