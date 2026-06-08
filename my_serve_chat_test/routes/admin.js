import express from 'express';
import { authenticateToken, requireSuperuser } from '../middleware/auth.js';
import {
  exportAccounting,
  exportAccountingTransactions,
  exportAccountingXlsx,
} from '../controllers/adminAccountingController.js';
import {
  getTeacherScheduleHeatmap,
  getTeacherPlacementPlan,
  getTeacherScheduleOverview,
  getTeacherScheduleTeachers,
} from '../controllers/teacherScheduleController.js';
import { getNagavisor } from '../controllers/nagavisorController.js';
import { adminResetUserPassword } from '../controllers/auth/index.js';
import {
  getTeacherBalanceAdmin,
  listTeacherBalancesAdmin,
  postTeacherBalanceTransactionAdmin,
  syncTeacherBalancesAdmin,
} from '../controllers/teacherBalanceController.js';

const router = express.Router();

// Админские маршруты: суперпользователь (privateAccess не требуется)
router.use(authenticateToken, requireSuperuser);

router.get('/accounting/teacher-balances', listTeacherBalancesAdmin);
router.get('/accounting/teacher-balances/:teacherId', getTeacherBalanceAdmin);
router.post('/accounting/teacher-balances/:teacherId/transactions', postTeacherBalanceTransactionAdmin);
router.post('/accounting/teacher-balances/sync', syncTeacherBalancesAdmin);
router.get('/accounting/teacher-schedule/teachers', getTeacherScheduleTeachers);
router.get('/accounting/teacher-schedule', getTeacherScheduleHeatmap);
router.get('/accounting/teacher-schedule/overview', getTeacherScheduleOverview);
router.get('/accounting/teacher-schedule/placement', getTeacherPlacementPlan);
router.get('/accounting/nagavisor', getNagavisor);
router.get('/accounting/export', exportAccounting);
router.get('/accounting/transactions-export', exportAccountingTransactions);
router.get('/accounting/export-xlsx', exportAccountingXlsx);
router.post('/reset-user-password', adminResetUserPassword);

export default router;

