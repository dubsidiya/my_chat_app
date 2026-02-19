import express from 'express';
import rateLimit from 'express-rate-limit';
import { register, login, getMe, updateProfile, uploadAvatar, getAllUsers, getUserById, deleteAccount, changePassword, unlockPrivateAccess, saveFcmToken } from '../controllers/authController.js';
import { authenticateToken } from '../middleware/auth.js';
import { uploadImage } from '../utils/uploadImage.js';

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

// Защищенные эндпоинты (требуют JWT токен)
router.get('/me', authenticateToken, getMe);
router.patch('/me', authenticateToken, updateProfile); // PATCH /auth/me — обновить ник (display_name)
router.post('/me/avatar', authenticateToken, uploadImage.single('avatar'), uploadAvatar); // POST /auth/me/avatar — загрузить аватар
router.get('/users', authenticateToken, getAllUsers); // GET /auth/users - получение всех пользователей
router.get('/users/:userId', authenticateToken, getUserById); // GET /auth/users/:userId - профиль пользователя (аватар/ник)
router.delete('/user/:userId', authenticateToken, deleteAccount); // DELETE /auth/user/:userId - удаление аккаунта
router.put('/user/:userId/password', authenticateToken, changePassword); // PUT /auth/user/:userId/password - смена пароля
router.post('/unlock-private', authenticateToken, unlockLimiter, unlockPrivateAccess); // POST /auth/unlock-private - получить токен с privateAccess=true
router.post('/fcm-token', authenticateToken, saveFcmToken); // POST /auth/fcm-token - сохранить FCM-токен для push

export default router;
