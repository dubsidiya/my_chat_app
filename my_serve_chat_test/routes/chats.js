import express from 'express';
import { getChatsList, getUserChats, createChat, deleteChat, getChatMembers, addMembersToChat, removeMemberFromChat, leaveChat } from '../controllers/chatsController.js';
import { authenticateToken } from '../middleware/auth.js';

const router = express.Router();

// Все роуты чатов требуют аутентификации
router.use(authenticateToken);

// Более специфичные роуты должны быть раньше общих
router.get('/', getChatsList); // GET /chats - список чатов с last message + unread
router.post('/:id/leave', leaveChat); // POST /chats/:id/leave - выход из чата
router.get('/:id/members', getChatMembers); // GET /chats/:id/members
router.post('/:id/members', addMembersToChat); // POST /chats/:id/members
router.delete('/:id/members/:userId', removeMemberFromChat); // DELETE /chats/:id/members/:userId
router.get('/:id', getUserChats); // GET /chats/:id
router.post('/', createChat); // POST /chats
router.delete('/:id', deleteChat); // DELETE /chats/:id

export default router;
