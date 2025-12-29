import express from 'express';
import { setupCorsEndpoint } from '../controllers/setupController.js';
import { authenticateToken } from '../middleware/auth.js';

const router = express.Router();

// Эндпоинт для настройки CORS (требует аутентификации)
router.post('/cors', authenticateToken, setupCorsEndpoint);

export default router;

