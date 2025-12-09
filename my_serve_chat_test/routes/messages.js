import express from 'express';
import { getMessages, sendMessage, deleteMessage, clearChat } from '../controllers/messagesController.js';

const router = express.Router();

router.get('/:chatId', getMessages);
router.post('/', sendMessage);
router.delete('/message/:messageId', deleteMessage); // DELETE /messages/message/:messageId
router.delete('/:chatId', clearChat); // DELETE /messages/:chatId

export default router;
