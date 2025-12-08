import express from 'express';
import { getMessages, sendMessage, clearChat } from '../controllers/messagesController.js';

const router = express.Router();

router.get('/:chatId', getMessages);
router.post('/', sendMessage);
router.delete('/:chatId', clearChat); // DELETE /messages/:chatId

export default router;
