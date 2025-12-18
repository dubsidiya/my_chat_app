import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
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
router.get('/', getAllStudents);
router.post('/', createStudent);
router.put('/:id', updateStudent);
router.delete('/:id', deleteStudent);
router.get('/:id/balance', getStudentBalance);
router.get('/:id/transactions', getStudentTransactions);

// Маршруты для занятий
router.get('/:studentId/lessons', getStudentLessons);
router.post('/:studentId/lessons', createLesson);
router.delete('/lessons/:id', deleteLesson);

// Маршруты для транзакций
router.post('/:studentId/deposit', depositBalance);

export default router;

