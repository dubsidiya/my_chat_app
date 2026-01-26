import { setupCors } from '../utils/setupCors.js';

/**
 * Эндпоинт для настройки CORS в Яндекс Object Storage
 * Вызовите один раз: POST /setup/cors
 * Требует аутентификации для безопасности
 */
export const setupCorsEndpoint = async (req, res) => {
  try {
    console.log('🔧 Запрос на настройку CORS получен');
    
    // Проверяем переменные окружения
    if (!process.env.YANDEX_ACCESS_KEY_ID || 
        !process.env.YANDEX_SECRET_ACCESS_KEY || 
        !process.env.YANDEX_BUCKET_NAME) {
      return res.status(400).json({
        success: false,
        message: 'Переменные Яндекс Object Storage не настроены',
        required: [
          'YANDEX_ACCESS_KEY_ID',
          'YANDEX_SECRET_ACCESS_KEY',
          'YANDEX_BUCKET_NAME'
        ]
      });
    }

    // Настраиваем CORS
    await setupCors();

    res.status(200).json({
      success: true,
      message: 'CORS успешно настроен для бакета',
      bucket: process.env.YANDEX_BUCKET_NAME,
      corsRules: {
        allowedOrigins: ['*'],
        allowedMethods: ['GET', 'HEAD', 'OPTIONS'],
        allowedHeaders: ['*'],
        maxAgeSeconds: 3600
      }
    });
  } catch (error) {
    console.error('Ошибка настройки CORS:', error);
    
    let errorMessage = 'Ошибка настройки CORS';
    if (error.name === 'NoSuchBucket') {
      errorMessage = `Бакет "${process.env.YANDEX_BUCKET_NAME}" не найден`;
    } else if (error.name === 'AccessDenied' || error.message.includes('Access Denied')) {
      errorMessage = 'Доступ запрещен. Проверьте ключи доступа и права сервисного аккаунта';
    } else {
      errorMessage = error.message || errorMessage;
    }

    res.status(500).json({
      success: false,
      message: errorMessage,
    });
  }
};

