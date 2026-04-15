import express from 'express';
import {
  createChat,
  deleteChat,
  getChatById,
  getChatsList,
  getUserChats,
  renameChat,
} from '../../controllers/chats/index.js';

const router = express.Router();

router.get('/', getChatsList);
router.get('/all', getUserChats);
router.get('/:id', getChatById);
router.post('/', createChat);
router.delete('/:id', deleteChat);
router.put('/:id/name', renameChat);

export default router;
