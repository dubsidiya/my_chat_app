import express from 'express';
import { register, login, getAllUsers, deleteAccount } from '../controllers/authController.js';

const router = express.Router();

router.post('/register', register);
router.post('/login', login);
router.get('/users', getAllUsers); // GET /auth/users - получение всех пользователей
router.delete('/user/:userId', deleteAccount); // DELETE /auth/user/:userId - удаление аккаунта

export default router;
