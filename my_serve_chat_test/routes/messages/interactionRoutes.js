import express from 'express';
import {
  addReaction,
  markMessageAsRead,
  markMessagesAsRead,
  pinMessage,
  removeReaction,
  unpinMessage,
} from '../../controllers/messages/index.js';

const router = express.Router();

router.post('/message/:messageId/read', markMessageAsRead);
router.post('/chat/:chatId/read-all', markMessagesAsRead);
router.post('/message/:messageId/pin', pinMessage);
router.delete('/message/:messageId/pin', unpinMessage);
router.post('/message/:messageId/reaction', addReaction);
router.delete('/message/:messageId/reaction', removeReaction);

export default router;
