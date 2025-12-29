import express from 'express';
import { setupCorsEndpoint } from '../controllers/setupController.js';
import { authenticateToken } from '../middleware/auth.js';

const router = express.Router();

// Эндпоинт для настройки CORS
// Можно вызвать без аутентификации для удобства (один раз для настройки)
// В продакшене можно добавить простую защиту через секретный ключ
const setupSecret = process.env.SETUP_SECRET || 'setup-cors-2024';
router.post('/cors', (req, res, next) => {
  // Проверяем секретный ключ или токен
  const authHeader = req.headers.authorization;
  const secret = req.body.secret || req.query.secret;
  
  if (secret === setupSecret) {
    // Если передан правильный секрет, пропускаем без аутентификации
    return next();
  }
  
  // Иначе проверяем токен
  authenticateToken(req, res, next);
}, setupCorsEndpoint);

export default router;

