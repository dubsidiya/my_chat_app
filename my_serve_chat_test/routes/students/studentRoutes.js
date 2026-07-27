import express from 'express';
import {
  archiveStudent,
  createStudent,
  deleteStudent,
  deleteStudentFull,
  getAllStudents,
  getMakeupPendingSummary,
  getStudentBalance,
  getStudentTransactions,
  linkExistingStudent,
  unarchiveStudent,
  updateStudent,
} from '../../controllers/students/index.js';

const router = express.Router();

router.get('/', getAllStudents);
router.get('/makeup-pending', getMakeupPendingSummary);
router.post('/', createStudent);
router.post('/link-existing', linkExistingStudent);
router.put('/:id', updateStudent);
router.post('/:id/archive', archiveStudent);
router.post('/:id/unarchive', unarchiveStudent);
router.delete('/:id', deleteStudent);
router.delete('/:id/full', deleteStudentFull);
router.get('/:id/balance', getStudentBalance);
router.get('/:id/transactions', getStudentTransactions);

export default router;
