import express from 'express';
import multer from 'multer';
import { authenticateToken, requireSuperuser } from '../middleware/auth.js';
import { upload, processBankStatement, applyPayments } from '../controllers/bankStatementController.js';

const router = express.Router();

// Бухгалтерия: только суперпользователь
router.use(authenticateToken, requireSuperuser);

// Загрузка и обработка файла выписки (предпросмотр)
router.post('/upload', upload.single('file'), processBankStatement);

// Применение платежей (создание транзакций)
router.post('/apply', applyPayments);

// M26: ошибки загрузки файла превращаем в понятный 400, а не в общий 500.
// В этом роутере в next(err) попадают только ошибки из upload.single('file'):
// - multer.MulterError (напр. LIMIT_FILE_SIZE — файл слишком большой);
// - ошибки fileFilter (неподдерживаемый формат, Excel отключён) — обычные Error.
// Контроллеры свои ошибки обрабатывают сами и сюда их не пробрасывают.
// eslint-disable-next-line no-unused-vars
router.use((err, req, res, next) => {
  if (!err) return next();
  if (res.headersSent) return next(err);
  if (err instanceof multer.MulterError) {
    const message =
      err.code === 'LIMIT_FILE_SIZE'
        ? 'Файл слишком большой (макс 10MB)'
        : err.message || 'Ошибка загрузки файла';
    return res.status(400).json({ message });
  }
  // Ошибки fileFilter содержат исходный человекочитаемый текст — отдаём его как есть.
  return res.status(400).json({ message: err.message || 'Некорректный файл выписки' });
});

export default router;

