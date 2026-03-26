import express from 'express';
import rateLimit from 'express-rate-limit';
import {
  createInvite,
  joinByInvite,
  revokeInvite,
} from '../../controllers/chats/index.js';

const router = express.Router();

const joinInviteLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 25,
  message: { message: 'Слишком много попыток вступления по инвайту, попробуйте позже' },
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => (req.ip || req.connection?.remoteAddress || 'unknown').toString(),
});

router.post('/:id/invites', createInvite);
router.post('/join', joinInviteLimiter, joinByInvite);
router.post('/:id/invites/:inviteId/revoke', revokeInvite);

export default router;
