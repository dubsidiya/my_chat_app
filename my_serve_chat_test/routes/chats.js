import express from 'express';
import { authenticateToken } from '../middleware/auth.js';
import chatRoutes from './chats/chatRoutes.js';
import folderRoutes from './chats/folderRoutes.js';
import memberRoutes from './chats/memberRoutes.js';
import inviteRoutes from './chats/inviteRoutes.js';

const router = express.Router();

// Все роуты чатов требуют аутентификации
router.use(authenticateToken);

router.use(folderRoutes);
router.use(memberRoutes);
router.use(inviteRoutes);
router.use(chatRoutes);

export default router;
