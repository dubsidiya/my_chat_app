import express from 'express';
import {
  createChatFolder,
  deleteChatFolder,
  getChatFolders,
  renameChatFolder,
  setChatFolder,
} from '../../controllers/chats/index.js';

const router = express.Router();

router.get('/folders', getChatFolders);
router.post('/folders', createChatFolder);
router.put('/folders/:folderId', renameChatFolder);
router.delete('/folders/:folderId', deleteChatFolder);
router.put('/:id/folder', setChatFolder);

export default router;
