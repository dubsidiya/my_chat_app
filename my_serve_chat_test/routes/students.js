import express from 'express';
import { authenticateToken, requirePrivateAccess, requireSuperuser } from '../middleware/auth.js';
import {
  getAllStudents,
  createStudent,
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
  depositBalance
} from '../controllers/transactionsController.js';

const router = express.Router();

// Все маршруты требуют аутентификации
router.use(authenticateToken);

// Маршруты для студентов
router.get('/', requirePrivateAccess, getAllStudents);
router.post('/', requirePrivateAccess, createStudent);
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

export default router;

