import express from 'express';
import { authenticateToken, requireSuperuser } from '../middleware/auth.js';
import { upload, processBankStatement, applyPayments } from '../controllers/bankStatementController.js';

const router = express.Router();

// Бухгалтерия: только суперпользователь
router.use(authenticateToken, requireSuperuser);

// Загрузка и обработка файла выписки (предпросмотр)
router.post('/upload', upload.single('file'), processBankStatement);

// Применение платежей (создание транзакций)
router.post('/apply', applyPayments);

export default router;

