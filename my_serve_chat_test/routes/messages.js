import express from 'express';
import { getMessages, sendMessage, deleteMessage, clearChat, uploadImage } from '../controllers/messagesController.js';
import { authenticateToken } from '../middleware/auth.js';
import { uploadImage as uploadImageMiddleware } from '../utils/uploadImage.js';

const router = express.Router();

// Все роуты сообщений требуют аутентификации
router.use(authenticateToken);

router.get('/:chatId', getMessages);
router.post('/', sendMessage);
router.post('/upload-image', uploadImageMiddleware.single('image'), uploadImage); // POST /messages/upload-image
router.delete('/message/:messageId', deleteMessage); // DELETE /messages/message/:messageId
router.delete('/:chatId', clearChat); // DELETE /messages/:chatId

export default router;
