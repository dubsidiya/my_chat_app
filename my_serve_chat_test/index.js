import express from 'express';
import cors from 'cors';
import bodyParser from 'body-parser';
import dotenv from 'dotenv';
import http from 'http';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
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
import moderationRoutes from './routes/moderation.js';
import e2eeRoutes from './routes/e2ee.js';
import { setupWebSocket } from './websocket/websocket.js';
import pool from './db.js';

dotenv.config();

const app = express();
app.disable('x-powered-by'); // Не раскрывать клиенту технологию сервера
const server = http.createServer(app);

// Health check endpoint (для keep-alive пинга на Render free tier)
// ?warm=1 — дополнительно прогревает соединение с БД, чтобы после пробуждения первый запрос не таймаутил
app.get('/healthz', (req, res) => {
  if (req.query.warm === '1') {
    pool.query('SELECT 1').then(() => res.status(200).send('ok')).catch(() => res.status(200).send('ok'));
    return;
  }
  res.status(200).send('ok');
});

// Метаданные сервера (диагностика). В production отключено — не раскрывать окружение.
if (process.env.NODE_ENV !== 'production') {
  app.get('/_meta', async (req, res) => {
  const startedAt = new Date(Date.now() - Math.floor(process.uptime() * 1000)).toISOString();
  const dbUrlRaw = process.env.DATABASE_URL || '';
  let db = null;
  try {
    if (dbUrlRaw) {
      const u = new URL(dbUrlRaw);
      db = {
        host: u.hostname,
        port: u.port ? parseInt(u.port, 10) : null,
        database: (u.pathname || '').replace(/^\//, '') || null,
        sslmode: u.searchParams.get('sslmode') || null,
      };
    }
  } catch (_) {
    db = { host: null, port: null, database: null, sslmode: null };
  }

  let dbOk = false;
  try {
    await pool.query('SELECT 1');
    dbOk = true;
  } catch (_) {
    dbOk = false;
  }

  res.status(200).json({
    now: new Date().toISOString(),
    startedAt,
    uptimeSeconds: Math.floor(process.uptime()),
    node: process.version,
    env: process.env.NODE_ENV || 'development',
    port: process.env.PORT || 3000,
    firebase: {
      configured: Boolean(
        (process.env.FIREBASE_PROJECT_ID &&
          process.env.FIREBASE_CLIENT_EMAIL &&
          process.env.FIREBASE_PRIVATE_KEY) ||
          process.env.FIREBASE_SERVICE_ACCOUNT_PATH ||
          process.env.FIREBASE_SERVICE_ACCOUNT_JSON
      ),
      credentialSource: process.env.FIREBASE_SERVICE_ACCOUNT_PATH
        ? 'path'
        : process.env.FIREBASE_SERVICE_ACCOUNT_JSON
          ? 'json'
          : (process.env.FIREBASE_PROJECT_ID &&
              process.env.FIREBASE_CLIENT_EMAIL &&
              process.env.FIREBASE_PRIVATE_KEY)
            ? 'parts'
            : 'none',
    },
    db,
    dbOk,
    allowedOrigins: process.env.ALLOWED_ORIGINS || null,
    allowedOriginPatterns: process.env.ALLOWED_ORIGIN_PATTERNS || null,
    appMinVersion: process.env.APP_MIN_VERSION || null,
    appLatestVersion: process.env.APP_LATEST_VERSION || null,
  });
  });
} else {
  app.get('/_meta', (req, res) => res.status(404).json({ message: 'Не найдено' }));
}

// Проверка версии приложения: клиент сравнивает свою версию с min/latest и показывает «Обновите» при необходимости.
// Переменные в .env: APP_MIN_VERSION (обязательное обновление ниже этой версии), APP_LATEST_VERSION (рекомендуемое),
// APP_FORCE_UPDATE (true/false — трактовать ли устаревшую версию как блокирующую), APP_STORE_URL_ANDROID, APP_STORE_URL_IOS.
app.get('/version', (req, res) => {
  const minVersion = process.env.APP_MIN_VERSION || process.env.APP_LATEST_VERSION || '0.0.0';
  const latestVersion = process.env.APP_LATEST_VERSION || minVersion;
  const forceUpdate = process.env.APP_FORCE_UPDATE === 'true' || process.env.APP_FORCE_UPDATE === '1';
  res.json({
    minVersion,
    latestVersion,
    forceUpdate,
    message: process.env.APP_VERSION_MESSAGE || 'Доступна новая версия приложения. Обновите для корректной работы.',
    storeUrlAndroid: process.env.APP_STORE_URL_ANDROID || null,
    storeUrlIos: process.env.APP_STORE_URL_IOS || null,
  });
});

// В production JWT_SECRET обязателен и не короче 32 символов
const JWT_SECRET = process.env.JWT_SECRET;
if (process.env.NODE_ENV === 'production') {
  if (!JWT_SECRET || typeof JWT_SECRET !== 'string') {
    console.error('❌ JWT_SECRET НЕ УСТАНОВЛЕН! Сервер не может безопасно запуститься в production.');
    process.exit(1);
  }
  if (JWT_SECRET.length < 32) {
    console.error('❌ JWT_SECRET должен быть не короче 32 символов в production.');
    process.exit(1);
  }
}

// Настройка trust proxy: 1 = доверять только первому прокси (Render).
// true запрещён express-rate-limit (позволяет подделку IP). Число 1 даёт корректный client IP и проходит валидацию.
app.set('trust proxy', 1);

// Helmet — набор security-заголовков (X-Content-Type-Options, X-Frame-Options и др.)
app.use(helmet({
  contentSecurityPolicy: false, // API не отдаёт HTML
  crossOriginEmbedderPolicy: false,
}));
// Дополнительно: жёсткий DENY для iframe и HSTS в production
app.use((req, res, next) => {
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  if (process.env.NODE_ENV === 'production') {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
  }
  next();
});

const isProduction = process.env.NODE_ENV === 'production';
const enablePreviewOrigins = process.env.ENABLE_PREVIEW_ORIGIN_PATTERNS === 'true' || process.env.ENABLE_PREVIEW_ORIGIN_PATTERNS === '1';

// Настройка CORS:
// - production: только явные origin из ALLOWED_ORIGINS
// - development: ALLOWED_ORIGINS + localhost
const envAllowedOrigins = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map(o => o.trim()).filter(Boolean)
  : [];
if (isProduction && envAllowedOrigins.length === 0) {
  console.error('❌ В production необходимо задать ALLOWED_ORIGINS в .env (точные origin, без wildcard).');
  process.exit(1);
}

const devDefaultOrigins = [
  'http://localhost:3000',
  'http://localhost:8080',
  'http://127.0.0.1:3000',
  'http://127.0.0.1:8080',
];
const allAllowedOrigins = [
  ...new Set(isProduction ? envAllowedOrigins : [...envAllowedOrigins, ...devDefaultOrigins]),
];

const allowedOriginPatterns = enablePreviewOrigins && process.env.ALLOWED_ORIGIN_PATTERNS
  ? process.env.ALLOWED_ORIGIN_PATTERNS.split(',').map(p => p.trim()).filter(Boolean)
  : [];

app.use(cors({
  origin: function (origin, callback) {
    // Разрешаем запросы без origin (мобильные приложения, Flutter, Postman и т.д.)
    if (!origin) {
      if (process.env.NODE_ENV === 'development') {
        console.log('CORS: Запрос без origin (мобильное приложение) - разрешено');
      }
      return callback(null, true);
    }
    
    // Нормализуем origin (без path/query) и вытаскиваем hostname/protocol для pattern-проверок
    let originUrl = null;
    let normalizedOrigin = origin;
    try {
      originUrl = new URL(origin);
      normalizedOrigin = `${originUrl.protocol}//${originUrl.hostname}${originUrl.port ? `:${originUrl.port}` : ''}`;
    } catch (_) {
      // origin может быть невалидным URL; оставляем как есть
    }

    // Проверяем точное совпадение
    if (allAllowedOrigins.indexOf(origin) !== -1 || allAllowedOrigins.indexOf(normalizedOrigin) !== -1) {
      if (process.env.NODE_ENV === 'development') {
        console.log(`CORS: Разрешен origin (точное совпадение): ${origin}`);
      }
      return callback(null, true);
    }
    
    // Проверяем localhost в любом виде (для разработки)
    if (!isProduction && (origin.includes('localhost') || origin.includes('127.0.0.1'))) {
      if (process.env.NODE_ENV === 'development') {
        console.log(`CORS: Разрешен localhost origin: ${origin}`);
      }
      return callback(null, true);
    }
    
    // Pattern/wildcard поддержка (управляется через ALLOWED_ORIGIN_PATTERNS)
    // Примеры:
    // - ALLOWED_ORIGIN_PATTERNS=https://*.vercel.app
    // - ALLOWED_ORIGIN_PATTERNS=my-chat-app-*.vercel.app,*.netlify.app
    if (allowedOriginPatterns.length > 0 && originUrl) {
      const host = originUrl.hostname.toLowerCase();
      const proto = originUrl.protocol.toLowerCase();

      const matchesPattern = (pattern) => {
        // pattern может быть:
        // - https://*.vercel.app
        // - *.vercel.app
        // - my-chat-app-*.vercel.app
        // - https://mydomain.com
        const raw = pattern.trim();
        if (!raw) return false;

        // Если указана схема — проверяем её отдельно
        let patternProto = null;
        let patternHost = raw;
        if (raw.includes('://')) {
          const parts = raw.split('://');
          patternProto = `${parts[0].toLowerCase()}:`;
          patternHost = parts.slice(1).join('://');
        }

        if (patternProto && patternProto !== proto) return false;

        // Превращаем wildcard в regex по hostname
        const escaped = patternHost
          .toLowerCase()
          .replace(/[.+?^${}()|[\]\\]/g, '\\$&')
          .replace(/\*/g, '.*');
        const re = new RegExp(`^${escaped}$`);
        return re.test(host);
      };

      if (allowedOriginPatterns.some(matchesPattern)) {
        if (process.env.NODE_ENV === 'development') {
          console.log(`CORS: Разрешен origin (pattern): ${origin} (host: ${host})`);
        }
        return callback(null, true);
      }
    }
    
    if (process.env.NODE_ENV === 'development') {
      console.log(`CORS: Заблокирован origin: ${origin}`);
      console.log(`CORS: Разрешенные origins: ${allAllowedOrigins.join(', ')}`);
      if (allowedOriginPatterns.length > 0) {
        console.log(`CORS: Разрешенные patterns: ${allowedOriginPatterns.join(', ')}`);
      }
    }
    callback(new Error(`Not allowed by CORS: ${origin}`));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key', 'X-Client-Timezone', 'X-Refresh-Token'],
  optionsSuccessStatus: 204
}));

// Лимит размера тела запроса — защита от DoS большими JSON
const JSON_LIMIT = '512kb';
const URLENC_LIMIT = '512kb';
app.use(bodyParser.json({ limit: JSON_LIMIT }));
app.use(bodyParser.urlencoded({ extended: true, limit: URLENC_LIMIT }));

// Раздача статических файлов (изображения) - больше не нужна, т.к. файлы в Яндекс Облаке
// Закомментировано, но можно оставить для обратной совместимости
// const __filename = fileURLToPath(import.meta.url);
// const __dirname = path.dirname(__filename);
// app.use('/uploads/images', express.static(path.join(__dirname, 'uploads/images')));

// Вспомогательная функция для получения клиентского IP (корректно за Render/Vercel прокси)
const getClientIp = (req) => {
  // Trust proxy: 1 — req.ip берётся из X-Forwarded-For. На Render без trust proxy все видят один IP балансировщика.
  const ip = req.ip || req.get?.('x-forwarded-for')?.split(',')[0]?.trim() || req.connection?.remoteAddress;
  return ip || 'unknown';
};

// Ключ rate limit для авторизованных API: IP + фрагмент bearer-токена.
// Это снижает ложные 429, когда несколько пользователей сидят за одним NAT/IP.
const getAuthAwareKey = (req, prefix = 'api') => {
  const ip = getClientIp(req);
  const auth = (req.get?.('authorization') || '').toString();
  const tokenPart = auth.toLowerCase().startsWith('bearer ')
    ? auth.slice(7).trim().slice(0, 24)
    : 'anon';
  return `${prefix}_${ip}_${tokenPart}`;
};
const isProd = process.env.NODE_ENV === 'production';

// Глобальный rate limit (последняя линия от DoS — все запросы с одного IP)
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  // Для мобильных клиентов за одним NAT/IP (эмулятор + устройство) прежний лимит
  // приводил к ложным 429 и ломал E2EE-обмен ключами.
  max: isProd ? 3000 : 50000,
  message: { message: 'Слишком много запросов с вашего адреса, попробуйте позже' },
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => getAuthAwareKey(req, 'global'),
});
app.use(globalLimiter);

// Rate limiting для защиты от брутфорса
// Ключ = username + IP: один пользователь с неверным паролем не блокирует остальных (важно при общем IP за прокси)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 минут
  max: 5, // максимум 5 неудачных попыток
  message: 'Слишком много попыток входа, попробуйте позже',
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true, // успешный вход не считается — блокируем только после 5 неудач
  keyGenerator: (req) => {
    const username = (req.body?.username || req.body?.email || '').toString().toLowerCase().trim() || 'anon';
    const ip = getClientIp(req);
    return `auth_${username}_${ip}`;
  },
});

// Общий rate limit для API (защита от DoS)
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: isProd ? 900 : 10000,
  message: 'Слишком много запросов, попробуйте позже',
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => getAuthAwareKey(req, 'api'),
});

// E2EE использует bursts при обмене ключами; выделяем более мягкий лимит.
const e2eeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: isProd ? 600 : 10000,
  message: 'Слишком много E2EE-запросов, попробуйте позже',
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => getAuthAwareKey(req, 'e2ee'),
});

// Более строгий лимит для загрузок
const uploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 40,
  message: 'Слишком много загрузок, попробуйте позже',
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => getClientIp(req),
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
app.use('/e2ee', e2eeLimiter);

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
app.use('/moderation', moderationRoutes);
app.use('/e2ee', e2eeRoutes);

// 404 — не раскрываем структуру API
app.use((req, res) => {
  res.status(404).json({ message: 'Не найдено' });
});

// Обработка ошибок (например, от CORS) — без утечки деталей
app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);
  res.status(500).json({ message: 'Ошибка сервера' });
});

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
