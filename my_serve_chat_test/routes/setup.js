import express from 'express';
import { setupCorsEndpoint } from '../controllers/setupController.js';
import { authenticateToken, requireSuperuser } from '../middleware/auth.js';

const router = express.Router();

// Эндпоинт для настройки CORS
// ВАЖНО: это чувствительная операция (управление конфигурацией storage),
// поэтому требуем суперпользователя. Никаких дефолтных секретов.
router.post('/cors', authenticateToken, requireSuperuser, setupCorsEndpoint);

export default router;

