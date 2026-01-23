import express from 'express';
import { authenticateToken, requireSuperuser } from '../middleware/auth.js';
import { exportAccounting } from '../controllers/adminAccountingController.js';

const router = express.Router();

// Админские маршруты: суперпользователь (privateAccess не требуется)
router.use(authenticateToken, requireSuperuser);

router.get('/accounting/export', exportAccounting);

export default router;

