import express from 'express';
import { authenticateToken, requirePrivateAccess } from '../middleware/auth.js';
import { upload, processBankStatement, applyPayments } from '../controllers/bankStatementController.js';

const router = express.Router();

// Все маршруты требуют аутентификации
router.use(authenticateToken, requirePrivateAccess);

// Загрузка и обработка файла выписки (предпросмотр)
router.post('/upload', upload.single('file'), processBankStatement);

// Применение платежей (создание транзакций)
router.post('/apply', applyPayments);

export default router;

