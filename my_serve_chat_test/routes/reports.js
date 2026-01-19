import express from 'express';
import { authenticateToken, requirePrivateAccess } from '../middleware/auth.js';
import {
  getAllReports,
  getReport,
  createReport,
  updateReport,
  deleteReport
} from '../controllers/reportsController.js';

const router = express.Router();

// Все маршруты требуют аутентификации
router.use(authenticateToken, requirePrivateAccess);

router.get('/', getAllReports);
router.get('/:id', getReport);
router.post('/', createReport);
router.put('/:id', updateReport);
router.delete('/:id', deleteReport);

export default router;

