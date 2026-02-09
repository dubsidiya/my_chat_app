import express from 'express';
import { getMessages, sendMessage, deleteMessage, clearChat, uploadImage, uploadFile, markMessageAsRead, markMessagesAsRead, editMessage, pinMessage, unpinMessage, addReaction, removeReaction, getPinnedMessages, searchMessages, getMessagesAround } from '../controllers/messagesController.js';
import { authenticateToken } from '../middleware/auth.js';
import { uploadImage as uploadImageMiddleware } from '../utils/uploadImage.js';
import { uploadFile as uploadFileMiddleware } from '../utils/uploadFile.js';

const router = express.Router();

// Все роуты сообщений требуют аутентификации
router.use(authenticateToken);

// Search & jump-to-message must be before generic /:chatId
router.get('/chat/:chatId/search', searchMessages); // GET /messages/chat/:chatId/search?q=...
router.get('/chat/:chatId/around/:messageId', getMessagesAround); // GET /messages/chat/:chatId/around/:messageId

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
      return res.status(400).json({ message: 'Ошибка загрузки файла' });
    }
    next();
  });
}, uploadImage); // POST /messages/upload-image

// Upload file (single field: file)
router.post('/upload-file', (req, res, next) => {
  uploadFileMiddleware.single('file')(req, res, (err) => {
    if (err) {
      console.error('Multer file error:', err);
      return res.status(400).json({ message: 'Ошибка загрузки файла' });
    }
    next();
  });
}, uploadFile); // POST /messages/upload-file
router.delete('/message/:messageId', deleteMessage); // DELETE /messages/message/:messageId
router.delete('/:chatId', clearChat); // DELETE /messages/:chatId

// ✅ Новые endpoints для статусов сообщений
router.post('/message/:messageId/read', markMessageAsRead); // POST /messages/message/:messageId/read
router.post('/chat/:chatId/read-all', markMessagesAsRead); // POST /messages/chat/:chatId/read-all

// ✅ Endpoints для закрепления сообщений
router.post('/message/:messageId/pin', pinMessage); // POST /messages/message/:messageId/pin
router.delete('/message/:messageId/pin', unpinMessage); // DELETE /messages/message/:messageId/pin
router.get('/chat/:chatId/pinned', getPinnedMessages); // GET /messages/chat/:chatId/pinned

// ✅ Endpoints для реакций
router.post('/message/:messageId/reaction', addReaction); // POST /messages/message/:messageId/reaction
router.delete('/message/:messageId/reaction', removeReaction); // DELETE /messages/message/:messageId/reaction

export default router;
