import express from 'express';
import { searchStudentSuggestions } from '../../controllers/students/index.js';

const router = express.Router();

router.get('/search', searchStudentSuggestions);

export default router;
