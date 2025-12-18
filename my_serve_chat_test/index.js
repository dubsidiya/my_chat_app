import express from 'express';
import cors from 'cors';
import bodyParser from 'body-parser';
import dotenv from 'dotenv';
import http from 'http';
import rateLimit from 'express-rate-limit';

import authRoutes from './routes/auth.js';
import chatRoutes from './routes/chats.js';
import messageRoutes from './routes/messages.js';
import studentsRoutes from './routes/students.js';
import { setupWebSocket } from './websocket/websocket.js';

dotenv.config();

const app = express();
const server = http.createServer(app);

// Настройка trust proxy для работы за прокси (Render.com, Cloudflare и т.д.)
// Это необходимо для правильной работы express-rate-limit
app.set('trust proxy', true);

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
      console.log('CORS: Запрос без origin (мобильное приложение) - разрешено');
      return callback(null, true);
    }
    
    // Проверяем точное совпадение
    if (allAllowedOrigins.indexOf(origin) !== -1) {
      console.log(`CORS: Разрешен origin (точное совпадение): ${origin}`);
      return callback(null, true);
    }
    
    // Проверяем localhost в любом виде (для разработки)
    if (origin.includes('localhost') || origin.includes('127.0.0.1')) {
      console.log(`CORS: Разрешен localhost origin: ${origin}`);
      return callback(null, true);
    }
    
    // Разрешаем все поддомены Vercel (для preview deployments)
    if (origin.includes('.vercel.app')) {
      console.log(`CORS: Разрешен Vercel origin: ${origin}`);
      return callback(null, true);
    }
    
    // Разрешаем все поддомены netlify (если используется)
    if (origin.includes('.netlify.app')) {
      console.log(`CORS: Разрешен Netlify origin: ${origin}`);
      return callback(null, true);
    }
    
    console.log(`CORS: Заблокирован origin: ${origin}`);
    console.log(`CORS: Разрешенные origins: ${allAllowedOrigins.join(', ')}`);
    callback(new Error('Not allowed by CORS'));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

app.use(bodyParser.json());

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

// Применяем rate limiting только к эндпоинтам аутентификации
app.use('/auth/login', authLimiter);
app.use('/auth/register', authLimiter);

app.use('/auth', authRoutes);
app.use('/chats', chatRoutes);
app.use('/messages', messageRoutes);
app.use('/students', studentsRoutes);

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
  console.log(`🔐 JWT_SECRET: ${process.env.JWT_SECRET ? 'установлен' : 'НЕ УСТАНОВЛЕН!'}`);
  console.log(`🌐 ALLOWED_ORIGINS: ${process.env.ALLOWED_ORIGINS || 'по умолчанию'}`);
  console.log(`🗄️  DATABASE_URL: ${process.env.DATABASE_URL ? 'установлен' : 'НЕ УСТАНОВЛЕН!'}`);
});

// Обработка необработанных ошибок
process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
});

process.on('uncaughtException', (error) => {
  console.error('❌ Uncaught Exception:', error);
  process.exit(1);
});
