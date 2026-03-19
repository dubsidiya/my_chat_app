import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import {
  uploadPublicKey,
  getPublicKey,
  getPublicKeys,
  storeChatKeys,
  getChatKey,
} from '../controllers/e2eeController.js';

const router = express.Router();

router.use(authenticateToken);

router.post('/public-key', uploadPublicKey);
router.get('/public-key/:userId', getPublicKey);
router.post('/public-keys', getPublicKeys);
router.post('/chat-keys', storeChatKeys);
router.get('/chat-key/:chatId', getChatKey);

export default router;
