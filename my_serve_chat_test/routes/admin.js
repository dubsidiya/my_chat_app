import express from 'express';
import { authenticateToken, requireSuperuser } from '../middleware/auth.js';
import {
  exportAccounting,
  exportAccountingTransactions,
  exportAccountingXlsx,
} from '../controllers/adminAccountingController.js';
import {
  getTeacherScheduleHeatmap,
  getTeacherScheduleTeachers,
} from '../controllers/teacherScheduleController.js';
import { adminResetUserPassword } from '../controllers/auth/index.js';

const router = express.Router();

// Админские маршруты: суперпользователь (privateAccess не требуется)
router.use(authenticateToken, requireSuperuser);

router.get('/accounting/teacher-schedule/teachers', getTeacherScheduleTeachers);
router.get('/accounting/teacher-schedule', getTeacherScheduleHeatmap);
router.get('/accounting/export', exportAccounting);
router.get('/accounting/transactions-export', exportAccountingTransactions);
router.get('/accounting/export-xlsx', exportAccountingXlsx);
router.post('/reset-user-password', adminResetUserPassword);

export default router;

