import express from 'express';
import { uploadImage, uploadFile } from '../../controllers/messages/index.js';
import { uploadImage as uploadImageMiddleware } from '../../utils/uploadImage.js';
import { uploadFile as uploadFileMiddleware } from '../../utils/uploadFile.js';

const router = express.Router();

router.post('/upload-image', (req, res, next) => {
  uploadImageMiddleware.fields([
    { name: 'image', maxCount: 1 },
    { name: 'original', maxCount: 1 },
  ])(req, res, (err) => {
    if (err) {
      console.error('Multer error:', err);
      return res.status(400).json({ message: 'Ошибка загрузки файла' });
    }
    next();
  });
}, uploadImage);

router.post('/upload-file', (req, res, next) => {
  uploadFileMiddleware.single('file')(req, res, (err) => {
    if (err) {
      console.error('Multer file error:', err);
      const msg = err.code === 'LIMIT_FILE_SIZE'
        ? 'Файл слишком большой. Максимум 100 МБ'
        : 'Ошибка загрузки файла';
      return res.status(400).json({ message: msg });
    }
    next();
  });
}, uploadFile);

export default router;
