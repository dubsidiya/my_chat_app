import express from 'express';
import {
  addMembersToChat,
  getChatMembers,
  leaveChat,
  removeMemberFromChat,
  transferOwnership,
  updateMemberRole,
} from '../../controllers/chats/index.js';

const router = express.Router();

router.post('/:id/leave', leaveChat);
router.post('/:id/transfer-ownership', transferOwnership);
router.get('/:id/members', getChatMembers);
router.post('/:id/members', addMembersToChat);
router.put('/:id/members/:userId/role', updateMemberRole);
router.delete('/:id/members/:userId', removeMemberFromChat);

export default router;
