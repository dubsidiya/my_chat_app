import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import {
  uploadPublicKey,
  getPublicKey,
  getPublicKeys,
  storeChatKeys,
  getChatKey,
  getSharedChatKey,
  setSharedChatKey,
  getMembersWithoutChatKey,
  requestChatKey,
  getPendingKeyRequests,
  storeKeyBackup,
  getKeyBackup,
} from '../controllers/e2ee/index.js';

const router = express.Router();

router.use(authenticateToken);

router.post('/public-key', uploadPublicKey);
router.get('/public-key/:userId', getPublicKey);
router.post('/public-keys', getPublicKeys);
router.post('/chat-keys', storeChatKeys);
router.get('/chat-key/:chatId', getChatKey);
router.get('/chat/:chatId/shared-key', getSharedChatKey);
router.post('/chat/:chatId/shared-key', setSharedChatKey);
router.get('/chat/:chatId/members-without-key', getMembersWithoutChatKey);
router.get('/chat/:chatId/key-requests', getPendingKeyRequests);
router.post('/chat/:chatId/request-key', requestChatKey);
router.post('/key-backup', storeKeyBackup);
router.get('/key-backup', getKeyBackup);

export default router;
