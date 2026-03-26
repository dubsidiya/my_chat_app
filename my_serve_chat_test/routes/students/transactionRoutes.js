import express from 'express';
import { deleteTransaction, depositBalance } from '../../controllers/transactionsController.js';

const router = express.Router();

router.post('/:studentId/deposit', depositBalance);
router.delete('/transactions/:id', deleteTransaction);

export default router;
