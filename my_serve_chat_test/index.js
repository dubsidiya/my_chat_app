import express from 'express';
import cors from 'cors';
import bodyParser from 'body-parser';
import dotenv from 'dotenv';
import http from 'http';
import rateLimit from 'express-rate-limit';
import path from 'path';
import { fileURLToPath } from 'url';

import authRoutes from './routes/auth.js';
import chatRoutes from './routes/chats.js';
import messageRoutes from './routes/messages.js';
import studentsRoutes from './routes/students.js';
import reportsRoutes from './routes/reports.js';
import bankStatementRoutes from './routes/bankStatement.js';
import setupRoutes from './routes/setup.js';
import adminRoutes from './routes/admin.js';
import { setupWebSocket } from './websocket/websocket.js';

dotenv.config();

const app = express();
const server = http.createServer(app);

// В production JWT_SECRET обязателен
if (process.env.NODE_ENV === 'production' && !process.env.JWT_SECRET) {
  console.error('❌ JWT_SECRET НЕ УСТАНОВЛЕН! Сервер не может безопасно запуститься в production.');
  process.exit(1);
}

// Настройка trust proxy для работы за прокси (Render.com, Cloudflare и т.д.)
// Это необходимо для правильной работы express-rate-limit
app.set('trust proxy', true);

// Базовые security headers (без дополнительных зависимостей)
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  next();
});

// Настройка CORS - ограничиваем только разрешенные домены
const allowedOrigins = process.env.ALLOWED_ORIGINS 
  ? process.env.ALLOWED_ORIGINS.split(',').map(o => o.trim())
  : ['http://localhost:3000', 'https://my-chat-app.vercel.app'];

// Добавляем стандартные домены для разработки
const defaultOrigins = [
  'http://localhost:3000',
  'http://localhost:8080',
  'http://127.0.0.1:3000',
  'http://127.0.0.1:8080',
  'https://my-chat-app.vercel.app'
];

const allAllowedOrigins = [...new Set([...allowedOrigins, ...defaultOrigins])];

app.use(cors({
  origin: function (origin, callback) {
    // Разрешаем запросы без origin (мобильные приложения, Flutter, Postman и т.д.)
    if (!origin) {
      if (process.env.NODE_ENV === 'development') {
        console.log('CORS: Запрос без origin (мобильное приложение) - разрешено');
      }
      return callback(null, true);
    }
    
    // Проверяем точное совпадение
    if (allAllowedOrigins.indexOf(origin) !== -1) {
      if (process.env.NODE_ENV === 'development') {
        console.log(`CORS: Разрешен origin (точное совпадение): ${origin}`);
      }
      return callback(null, true);
    }
    
    // Проверяем localhost в любом виде (для разработки)
    if (origin.includes('localhost') || origin.includes('127.0.0.1')) {
      if (process.env.NODE_ENV === 'development') {
        console.log(`CORS: Разрешен localhost origin: ${origin}`);
      }
      return callback(null, true);
    }
    
    // ВАЖНО: не разрешаем wildcard для *.vercel.app / *.netlify.app.
    // Если нужны preview-домены — добавляйте их явно в ALLOWED_ORIGINS.
    
    if (process.env.NODE_ENV === 'development') {
      console.log(`CORS: Заблокирован origin: ${origin}`);
      console.log(`CORS: Разрешенные origins: ${allAllowedOrigins.join(', ')}`);
    }
    callback(new Error('Not allowed by CORS'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Раздача статических файлов (изображения) - больше не нужна, т.к. файлы в Яндекс Облаке
// Закомментировано, но можно оставить для обратной совместимости
// const __filename = fileURLToPath(import.meta.url);
// const __dirname = path.dirname(__filename);
// app.use('/uploads/images', express.static(path.join(__dirname, 'uploads/images')));

// Rate limiting для защиты от брутфорса
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 минут
  max: 5, // максимум 5 запросов
  message: 'Слишком много попыток входа, попробуйте позже',
  standardHeaders: true,
  legacyHeaders: false,
  // Используем IP из заголовка X-Forwarded-For (когда trust proxy установлен)
  keyGenerator: (req) => {
    return req.ip || req.connection.remoteAddress;
  },
});

// Общий rate limit для API (защита от DoS)
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  message: 'Слишком много запросов, попробуйте позже',
  standardHeaders: true,
  legacyHeaders: false,
});

// Более строгий лимит для загрузок
const uploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 40,
  message: 'Слишком много загрузок, попробуйте позже',
  standardHeaders: true,
  legacyHeaders: false,
});

// Применяем rate limiting только к эндпоинтам аутентификации
app.use('/auth/login', authLimiter);
app.use('/auth/register', authLimiter);

// Общий лимит на основные API
app.use('/messages', apiLimiter);
app.use('/chats', apiLimiter);
app.use('/students', apiLimiter);
app.use('/reports', apiLimiter);
app.use('/admin', apiLimiter);
app.use('/bank-statement', apiLimiter);
app.use('/setup', apiLimiter);

// Строгий лимит на upload endpoints (messages + bank statement)
app.use('/messages/upload-image', uploadLimiter);
app.use('/messages/upload-file', uploadLimiter);
app.use('/bank-statement/upload', uploadLimiter);

app.use('/auth', authRoutes);
app.use('/chats', chatRoutes);
app.use('/messages', messageRoutes);
app.use('/students', studentsRoutes);
app.use('/reports', reportsRoutes);
app.use('/bank-statement', bankStatementRoutes);
app.use('/setup', setupRoutes);
app.use('/admin', adminRoutes);

// Подключение WebSocket
setupWebSocket(server);

const PORT = process.env.PORT || 3000;

// Обработка ошибок при запуске сервера
server.on('error', (err) => {
  console.error('❌ Ошибка сервера:', err);
  if (err.code === 'EADDRINUSE') {
    console.error(`Порт ${PORT} уже занят`);
  }
});

server.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📝 Environment: ${process.env.NODE_ENV || 'development'}`);
  // Не логируем наличие/отсутствие секретов и строк подключения в продакшене
  if (process.env.NODE_ENV === 'development') {
    console.log(`🌐 ALLOWED_ORIGINS: ${process.env.ALLOWED_ORIGINS || 'по умолчанию'}`);
  }
  
  // Проверка переменных Яндекс Object Storage
  const hasYandexConfig = process.env.YANDEX_ACCESS_KEY_ID && 
                          process.env.YANDEX_SECRET_ACCESS_KEY && 
                          process.env.YANDEX_BUCKET_NAME;
  if (hasYandexConfig) {
    console.log(`☁️  Яндекс Object Storage: настроен (бакет: ${process.env.YANDEX_BUCKET_NAME})`);
    
    // Автоматическая настройка CORS при старте (если не настроен)
    if (process.env.AUTO_SETUP_CORS !== 'false') {
      setTimeout(async () => {
        try {
          const { setupCors } = await import('./utils/setupCors.js');
          console.log('🔧 Автоматическая настройка CORS для бакета...');
          await setupCors();
          console.log('✅ CORS настроен автоматически! Изображения должны отображаться.');
        } catch (error) {
          console.warn('⚠️  Не удалось автоматически настроить CORS:', error.message);
          console.warn('   Это нормально, если CORS уже настроен или нет прав.');
          console.warn('   Вызовите вручную: POST /setup/cors с токеном авторизации');
          console.warn('   Или настройте CORS вручную в консоли Яндекс Облака (YANDEX_CLOUD_SETUP.md)');
        }
      }, 2000); // Ждем 2 секунды после запуска сервера
    }
  } else {
    console.log(`⚠️  Яндекс Object Storage: НЕ НАСТРОЕН (загрузка изображений не будет работать)`);
    console.log(`   Установите YANDEX_ACCESS_KEY_ID, YANDEX_SECRET_ACCESS_KEY, YANDEX_BUCKET_NAME`);
    console.log(`   См. инструкцию: YANDEX_CLOUD_SETUP.md`);
  }
});

// Обработка необработанных ошибок
process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
});

process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error);
  process.exit(1);
});
