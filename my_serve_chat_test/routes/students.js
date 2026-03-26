import express from 'express';
import { authenticateToken, requirePrivateAccess, requireSuperuser, isSuperuser } from '../middleware/auth.js';
import studentRoutes from './students/studentRoutes.js';
import searchRoutes from './students/searchRoutes.js';
import lessonRoutes from './students/lessonRoutes.js';
import transactionRoutes from './students/transactionRoutes.js';

const router = express.Router();

// Все маршруты требуют аутентификации
router.use(authenticateToken);

const requirePrivateOrSuperuser = (req, res, next) => {
  if (req.user?.privateAccess === true || isSuperuser(req.user)) return next();
  return res.status(403).json({ message: 'Требуется приватный доступ' });
};

router.use(requirePrivateOrSuperuser, searchRoutes);
router.use(requirePrivateAccess, studentRoutes);
router.use(requirePrivateAccess, lessonRoutes);
router.use(requireSuperuser, transactionRoutes);

export default router;

