import express from 'express';
import rateLimit from 'express-rate-limit';
import { register, login, requestPasswordReset, resetPassword, getAllUsers, deleteAccount, changePassword, unlockPrivateAccess } from '../controllers/authController.js';
import { authenticateToken } from '../middleware/auth.js';

const router = express.Router();

// Rate limiting для эндпоинта ввода приватного кода (анти-брутфорс)
const unlockLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 минут
  max: 10, // до 10 попыток
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Слишком много попыток, попробуйте позже' },
  keyGenerator: (req) => {
    // Ограничиваем по userId, если есть, иначе по IP
    return req.user?.userId?.toString() || req.ip;
  },
});

// Публичные эндпоинты (не требуют аутентификации)
router.post('/register', register);
router.post('/login', login);
router.post('/request-password-reset', requestPasswordReset);
router.post('/reset-password', resetPassword);

// Защищенные эндпоинты (требуют JWT токен)
router.get('/users', authenticateToken, getAllUsers); // GET /auth/users - получение всех пользователей
router.delete('/user/:userId', authenticateToken, deleteAccount); // DELETE /auth/user/:userId - удаление аккаунта
router.put('/user/:userId/password', authenticateToken, changePassword); // PUT /auth/user/:userId/password - смена пароля
router.post('/unlock-private', authenticateToken, unlockLimiter, unlockPrivateAccess); // POST /auth/unlock-private - получить токен с privateAccess=true

export default router;
