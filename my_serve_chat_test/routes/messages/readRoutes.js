import express from 'express';
import {
  getChatMedia,
  getMessages,
  getMessagesAround,
  getPinnedMessages,
  searchMessages,
} from '../../controllers/messages/index.js';

const router = express.Router();

router.get('/chat/:chatId/search', searchMessages);
router.get('/chat/:chatId/around/:messageId', getMessagesAround);
router.get('/chat/:chatId/media', getChatMedia);
router.get('/chat/:chatId/pinned', getPinnedMessages);
router.get('/:chatId', getMessages);

export default router;
