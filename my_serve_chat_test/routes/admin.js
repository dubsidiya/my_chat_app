import express from 'express';
import { authenticateToken, requirePrivateAccess, requireSuperuser } from '../middleware/auth.js';
import { exportAccounting } from '../controllers/adminAccountingController.js';

const router = express.Router();

// Админские маршруты: только с приватным доступом + суперпользователь
router.use(authenticateToken, requirePrivateAccess, requireSuperuser);

router.get('/accounting/export', exportAccounting);

export default router;

