import express from 'express';
import { getChatsList, getUserChats, createChat, deleteChat, getChatMembers, addMembersToChat, removeMemberFromChat, leaveChat, updateMemberRole, transferOwnership, createInvite, joinByInvite, revokeInvite, renameChat, setChatFolder } from '../controllers/chatsController.js';
import { authenticateToken } from '../middleware/auth.js';

const router = express.Router();

// Все роуты чатов требуют аутентификации
router.use(authenticateToken);

// Более специфичные роуты должны быть раньше общих
router.get('/', getChatsList); // GET /chats - список чатов с last message + unread
router.post('/:id/leave', leaveChat); // POST /chats/:id/leave - выход из чата
router.post('/:id/transfer-ownership', transferOwnership); // POST /chats/:id/transfer-ownership
router.post('/:id/invites', createInvite); // POST /chats/:id/invites
router.post('/join', joinByInvite); // POST /chats/join
router.post('/:id/invites/:inviteId/revoke', revokeInvite); // POST /chats/:id/invites/:inviteId/revoke
router.get('/:id/members', getChatMembers); // GET /chats/:id/members
router.post('/:id/members', addMembersToChat); // POST /chats/:id/members
router.put('/:id/members/:userId/role', updateMemberRole); // PUT /chats/:id/members/:userId/role
router.delete('/:id/members/:userId', removeMemberFromChat); // DELETE /chats/:id/members/:userId
router.put('/:id/name', renameChat); // PUT /chats/:id/name
router.put('/:id/folder', setChatFolder); // PUT /chats/:id/folder
router.get('/:id', getUserChats); // GET /chats/:id
router.post('/', createChat); // POST /chats
router.delete('/:id', deleteChat); // DELETE /chats/:id

export default router;
