import express from 'express';
import {
  createChat,
  deleteChat,
  getChatById,
  getChatsList,
  getSharedChatKey,
  getUserChats,
  renameChat,
} from '../../controllers/chats/index.js';

const router = express.Router();

router.get('/', getChatsList);
router.get('/all', getUserChats);
router.get('/:id/key', getSharedChatKey);
router.get('/:id', getChatById);
router.post('/', createChat);
router.delete('/:id', deleteChat);
router.put('/:id/name', renameChat);

export default router;
