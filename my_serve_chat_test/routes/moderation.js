import express from 'express';
import { reportMessage, blockUser, getBlockedUserIds } from '../controllers/moderationController.js';
import { authenticateToken } from '../middleware/auth.js';

const router = express.Router();
router.use(authenticateToken);

router.post('/report-message/:messageId', reportMessage);
router.post('/block-user', blockUser);
router.get('/blocked-ids', getBlockedUserIds);

export default router;
