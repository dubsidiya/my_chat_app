import express from 'express';
import {
  deleteTransaction,
  depositBalance,
  getStudentDepositTeachers,
} from '../../controllers/transactionsController.js';

const router = express.Router();

router.get('/:studentId/deposit-teachers', getStudentDepositTeachers);
router.post('/:studentId/deposit', depositBalance);
router.delete('/transactions/:id', deleteTransaction);

export default router;
