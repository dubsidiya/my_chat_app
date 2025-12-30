import express from 'express';
import { getMessages, sendMessage, deleteMessage, clearChat, uploadImage, markMessageAsRead, markMessagesAsRead, editMessage } from '../controllers/messagesController.js';
import { authenticateToken } from '../middleware/auth.js';
import { uploadImage as uploadImageMiddleware } from '../utils/uploadImage.js';

const router = express.Router();

// Все роуты сообщений требуют аутентификации
router.use(authenticateToken);

router.get('/:chatId', getMessages);
router.post('/', sendMessage);
router.put('/message/:messageId', editMessage); // PUT /messages/message/:messageId - редактирование сообщения
// Обработка ошибок multer (принимаем до 2 файлов: image и original)
router.post('/upload-image', (req, res, next) => {
  uploadImageMiddleware.fields([
    { name: 'image', maxCount: 1 },
    { name: 'original', maxCount: 1 }
  ])(req, res, (err) => {
    if (err) {
      console.error('Multer error:', err);
      return res.status(400).json({ 
        message: err.message || 'Ошибка загрузки файла',
        error: err.toString()
      });
    }
    next();
  });
}, uploadImage); // POST /messages/upload-image
router.delete('/message/:messageId', deleteMessage); // DELETE /messages/message/:messageId
router.delete('/:chatId', clearChat); // DELETE /messages/:chatId

// ✅ Новые endpoints для статусов сообщений
router.post('/message/:messageId/read', markMessageAsRead); // POST /messages/message/:messageId/read
router.post('/chat/:chatId/read-all', markMessagesAsRead); // POST /messages/chat/:chatId/read-all

export default router;
