import express from 'express';
import { authenticateToken, requirePrivateAccess, requireSuperuser } from '../middleware/auth.js';
import {
  getAllReports,
  getReportsList,
  getReport,
  getReportAudit,
  getMonthlySalaryReport,
  createReport,
  updateReport,
  deleteReport,
  setReportNotLate
} from '../controllers/reports/index.js';

const router = express.Router();

// Все маршруты требуют аутентификации
router.use(authenticateToken, requirePrivateAccess);

router.get('/salary', getMonthlySalaryReport);
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

