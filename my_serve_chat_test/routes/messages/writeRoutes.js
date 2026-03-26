import express from 'express';
import {
  clearChat,
  deleteMessage,
  editMessage,
  sendMessage,
} from '../../controllers/messages/index.js';

const router = express.Router();

router.post('/', sendMessage);
router.put('/message/:messageId', editMessage);
router.delete('/message/:messageId', deleteMessage);
router.delete('/:chatId', clearChat);

export default router;
