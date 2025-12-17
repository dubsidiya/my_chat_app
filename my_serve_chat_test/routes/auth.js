import express from 'express';
import { register, login, getAllUsers, deleteAccount, changePassword } from '../controllers/authController.js';
import { authenticateToken } from '../middleware/auth.js';

const router = express.Router();

// Публичные эндпоинты (не требуют аутентификации)
router.post('/register', register);
router.post('/login', login);

// Защищенные эндпоинты (требуют JWT токен)
router.get('/users', authenticateToken, getAllUsers); // GET /auth/users - получение всех пользователей
router.delete('/user/:userId', authenticateToken, deleteAccount); // DELETE /auth/user/:userId - удаление аккаунта
router.put('/user/:userId/password', authenticateToken, changePassword); // PUT /auth/user/:userId/password - смена пароля

export default router;
