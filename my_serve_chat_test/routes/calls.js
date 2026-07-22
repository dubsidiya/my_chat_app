import express from 'express';
import rateLimit from 'express-rate-limit';
import { authenticateToken } from '../middleware/auth.js';
import { issueLiveKitGroupToken } from '../controllers/livekitGroupCallsController.js';
import {
  realtimeRuntime,
  isRealtimeUnavailable,
} from '../realtime/index.js';
import { buildIceServersFromEnv } from '../services/calls/turnCredentials.js';

const router = express.Router();
const liveKitTokenLimiter = rateLimit({
  windowMs: 60_000,
  max: 12,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) =>
    `${String(req.userId || 'anonymous')}:${String(req.params.callId || '')}`,
  message: { error: 'rate_limited' },
});
const iceServersLimiter = rateLimit({
  windowMs: 60_000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => String(req.userId || req.ip || 'anonymous'),
  message: { error: 'rate_limited' },
});

/** GET /calls/ice-servers — STUN/TURN for WebRTC (auth required). */
router.get(
  '/ice-servers',
  authenticateToken,
  iceServersLimiter,
  (req, res) => {
    const payload = buildIceServersFromEnv(process.env, {
      userId: req.userId,
    });
    res.setHeader('Cache-Control', 'no-store');
    res.json({
      iceServers: payload.iceServers,
      ttl: payload.ttl,
      expiresAt: payload.expiresAt,
      credentialType: payload.credentialType,
      // Legacy clients only read iceServers; username/credential stay nested.
    });
  }
);

router.post(
  '/group/:callId/token',
  authenticateToken,
  liveKitTokenLimiter,
  issueLiveKitGroupToken
);

/**
 * Participant-scoped control-plane state. The response deliberately excludes
 * peer identity, connection ownership, credentials and tombstone details.
 */
router.get(
  '/status',
  (_req, res, next) => {
    res.setHeader('Cache-Control', 'no-store');
    next();
  },
  authenticateToken,
  async (req, res, next) => {
    const rawCallId = req.query.call_id ?? req.query.callId;
    if (
      rawCallId != null &&
      (typeof rawCallId !== 'string' || rawCallId.length > 128)
    ) {
      return res.status(200).json({ status: 'none', active: false });
    }
    const callId =
      typeof rawCallId === 'string' && rawCallId.length <= 128
        ? rawCallId.trim()
        : null;
    try {
      const status = await realtimeRuntime.registry.getStatus(req.userId, {
        callId,
      });
      return res.status(200).json({
        status: status.active ? status.state : 'none',
        ...status,
      });
    } catch (error) {
      if (!isRealtimeUnavailable(error)) return next(error);
      return res.status(503).json({
        status: 'unknown',
        active: null,
        available: false,
      });
    }
  }
);

export default router;
