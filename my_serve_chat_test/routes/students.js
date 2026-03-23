import express from 'express';
import { authenticateToken, requirePrivateAccess, requireSuperuser, isSuperuser } from '../middleware/auth.js';
import {
  getAllStudents,
  getMakeupPendingSummary,
  createStudent,
  searchStudentSuggestions,
  linkExistingStudent,
  updateStudent,
  deleteStudent,
  getStudentBalance,
  getStudentTransactions
} from '../controllers/studentsController.js';
import {
  getStudentLessons,
  createLesson,
  deleteLesson
} from '../controllers/lessonsController.js';
import {
  depositBalance,
  deleteTransaction
} from '../controllers/transactionsController.js';

const router = express.Router();

// Все маршруты требуют аутентификации
router.use(authenticateToken);

const requirePrivateOrSuperuser = (req, res, next) => {
  if (req.user?.privateAccess === true || isSuperuser(req.user)) return next();
  return res.status(403).json({ message: 'Требуется приватный доступ' });
};

// Маршруты для студентов
router.get('/', requirePrivateAccess, getAllStudents);
router.get('/makeup-pending', requirePrivateAccess, getMakeupPendingSummary);
router.post('/', requirePrivateAccess, createStudent);
router.get('/search', requirePrivateOrSuperuser, searchStudentSuggestions);
router.post('/link-existing', requirePrivateAccess, linkExistingStudent);
router.put('/:id', requirePrivateAccess, updateStudent);
router.delete('/:id', requirePrivateAccess, deleteStudent);
router.get('/:id/balance', requirePrivateAccess, getStudentBalance);
router.get('/:id/transactions', requirePrivateAccess, getStudentTransactions);

// Маршруты для занятий
router.get('/:studentId/lessons', requirePrivateAccess, getStudentLessons);
router.post('/:studentId/lessons', requirePrivateAccess, createLesson);
router.delete('/lessons/:id', requirePrivateAccess, deleteLesson);

// Маршруты для транзакций
// Пополнение баланса — только суперпользователь (бухгалтерия)
router.post('/:studentId/deposit', requireSuperuser, depositBalance);
// Undo пополнения — только суперпользователь (и только свои операции)
router.delete('/transactions/:id', requireSuperuser, deleteTransaction);

export default router;

