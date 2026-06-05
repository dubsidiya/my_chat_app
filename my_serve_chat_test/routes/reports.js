import express from 'express';
import { authenticateToken, requirePrivateAccess, requireSuperuser } from '../middleware/auth.js';
import {
  getAllReports,
  getReportAuthors,
  getReportsList,
  getReport,
  getReportAudit,
  getMonthlySalaryReport,
  createReport,
  updateReport,
  deleteReport,
  setReportNotLate
} from '../controllers/reports/index.js';
import {
  getMyTeacherBalance,
  getMyTeacherBalanceTransactions,
} from '../controllers/teacherBalanceController.js';

const router = express.Router();

// Все маршруты требуют аутентификации
router.use(authenticateToken, requirePrivateAccess);

router.get('/salary', getMonthlySalaryReport);
router.get('/balance/transactions', getMyTeacherBalanceTransactions);
router.get('/balance', getMyTeacherBalance);
router.get('/list/teachers', requireSuperuser, getReportAuthors);
router.get('/list', requireSuperuser, getReportsList);
router.get('/', getAllReports);
router.get('/:id/audit', getReportAudit);
router.get('/:id', getReport);
router.post('/', createReport);
router.put('/:id', updateReport);
router.delete('/:id', deleteReport);
// Снять пометку «поздний отчёт» — только суперпользователь
router.patch('/:id/set-not-late', requireSuperuser, setReportNotLate);

export default router;

