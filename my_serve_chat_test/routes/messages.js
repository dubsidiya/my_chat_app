import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import readRoutes from './messages/readRoutes.js';
import writeRoutes from './messages/writeRoutes.js';
import interactionRoutes from './messages/interactionRoutes.js';
import uploadRoutes from './messages/uploadRoutes.js';

const router = express.Router();

// Все роуты сообщений требуют аутентификации
router.use(authenticateToken);

router.use(readRoutes);
router.use(writeRoutes);
router.use(interactionRoutes);
router.use(uploadRoutes);

export default router;
