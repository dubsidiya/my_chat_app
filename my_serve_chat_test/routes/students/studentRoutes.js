import express from 'express';
import {
  createStudent,
  deleteStudent,
  deleteStudentFull,
  getAllStudents,
  getMakeupPendingSummary,
  getStudentBalance,
  getStudentTransactions,
  linkExistingStudent,
  updateStudent,
} from '../../controllers/students/index.js';

const router = express.Router();

router.get('/', getAllStudents);
router.get('/makeup-pending', getMakeupPendingSummary);
router.post('/', createStudent);
router.post('/link-existing', linkExistingStudent);
router.put('/:id', updateStudent);
router.delete('/:id', deleteStudent);
router.delete('/:id/full', deleteStudentFull);
router.get('/:id/balance', getStudentBalance);
router.get('/:id/transactions', getStudentTransactions);

export default router;
