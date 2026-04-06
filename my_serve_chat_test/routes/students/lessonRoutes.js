import express from 'express';
import {
  createLesson,
  deleteLesson,
  getLessonsCalendarSummary,
  getStudentLessons,
} from '../../controllers/lessons/index.js';

const router = express.Router();

router.get('/calendar-summary', getLessonsCalendarSummary);
router.get('/:studentId/lessons', getStudentLessons);
router.post('/:studentId/lessons', createLesson);
router.delete('/lessons/:id', deleteLesson);

export default router;
