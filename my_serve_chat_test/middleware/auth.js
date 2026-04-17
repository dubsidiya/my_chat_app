import jwt from 'jsonwebtoken';
import pool from '../db.js';

const JWT_SECRET = process.env.JWT_SECRET;
const ACCESS_TOKEN_TTL = process.env.JWT_ACCESS_TTL || '7d';
const WS_TOKEN_TTL_SECONDS = Number.parseInt(process.env.WS_TOKEN_TTL_SECONDS || '90', 10);
const SAFE_WS_TOKEN_TTL_SECONDS = Number.isFinite(WS_TOKEN_TTL_SECONDS)
  ? Math.min(Math.max(WS_TOKEN_TTL_SECONDS, 30), 300)
  : 90;
const REFRESH_JWT_SECRET = process.env.JWT_REFRESH_SECRET || JWT_SECRET;
const REFRESH_TOKEN_TTL_DAYS_RAW = Number.parseInt(process.env.JWT_REFRESH_TTL_DAYS || '30', 10);
const REFRESH_TOKEN_TTL_DAYS = Number.isFinite(REFRESH_TOKEN_TTL_DAYS_RAW)
  ? Math.min(Math.max(REFRESH_TOKEN_TTL_DAYS_RAW, 1), 90)
  : 30;

// Middleware для проверки JWT токена.
// После проверки подписи сверяет token_version (tv) из JWT с БД —
// токены, выданные до смены пароля/сброса, автоматически отклоняются.
export const authenticateToken = async (req, res, next) => {
  if (!JWT_SECRET) {
    return res.status(500).json({ message: 'JWT_SECRET не настроен на сервере' });
  }

  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (process.env.NODE_ENV === 'development') {
    console.log(`🔐 Auth check: ${req.method} ${req.path}`);
    console.log(`   Authorization header: ${authHeader ? 'present' : 'missing'}`);
  }

  if (!token) {
    if (process.env.NODE_ENV === 'development') {
      console.log('❌ No token provided');
    }
    return res.status(401).json({ message: 'Токен доступа отсутствует' });
  }

  const MAX_TOKEN_LENGTH = 4096;
  if (token.length > MAX_TOKEN_LENGTH) {
    return res.status(401).json({ message: 'Токен доступа отсутствует' });
  }

  try {
    const user = jwt.verify(token, JWT_SECRET, { algorithms: ['HS256'] });

    let dbVersion = 0;
    try {
      const row = await pool.query(
        'SELECT token_version FROM users WHERE id = $1',
        [user.userId]
      );
      if (row.rows.length === 0) {
        return res.status(401).json({ message: 'Пользователь не найден' });
      }
      dbVersion = row.rows[0].token_version ?? 0;
    } catch (dbErr) {
      if (dbErr?.code === '42703') {
        dbVersion = 0;
      } else {
        throw dbErr;
      }
    }

    const tokenVersion = user.tv ?? 0;
    if (tokenVersion !== dbVersion) {
      return res.status(401).json({ message: 'Сессия истекла. Пожалуйста, войдите заново' });
    }

    req.user = user;
    req.userId = user.userId;
    req.user.privateAccess = hasPrivateAccess(user);
    if (process.env.NODE_ENV === 'development') {
      console.log(`✅ JWT verified: userId=${user.userId}, username=${user.email || user.username}`);
    }
    next();
  } catch (err) {
    if (process.env.NODE_ENV === 'development') {
      console.error('JWT verification error:', err.message);
    }
    return res.status(403).json({ message: 'Недействительный токен' });
  }
};

// Генерация JWT токена
// username - логин пользователя (хранится в поле email в БД для обратной совместимости)
// tokenVersion - текущая версия из БД (users.token_version); при смене пароля инкрементируется
export const generateToken = (userId, username, privateAccess = false, tokenVersion = 0) => {
  if (!JWT_SECRET) {
    throw new Error('JWT_SECRET не настроен на сервере');
  }
  return jwt.sign(
    { userId, email: username, username: username, privateAccess: privateAccess === true, tv: tokenVersion },
    JWT_SECRET,
    { expiresIn: ACCESS_TOKEN_TTL, algorithm: 'HS256' }
  );
};

// Эфемерный токен только для подключения к WebSocket.
// Короткий TTL снижает риск утечек при перехвате в браузерном окружении.
export const generateWebSocketToken = (userId, username, tokenVersion = 0) => {
  if (!JWT_SECRET) {
    throw new Error('JWT_SECRET не настроен на сервере');
  }
  return jwt.sign(
    {
      userId,
      email: username,
      username: username,
      tv: tokenVersion,
      purpose: 'ws',
    },
    JWT_SECRET,
    { expiresIn: `${SAFE_WS_TOKEN_TTL_SECONDS}s`, algorithm: 'HS256' }
  );
};

// Middleware: доступ только к приватным разделам
export const requirePrivateAccess = (req, res, next) => {
  if (req.user?.privateAccess === true) {
    return next();
  }
  return res.status(403).json({ message: 'Требуется приватный доступ' });
};

// Утилита: проверка суперпользователя по env-настройкам
// - SUPERUSER_USERNAMES="admin,owner@example" (логины из users.email; сравнение case-insensitive)
// - SUPERUSER_USER_IDS="1,2,3"
export const isSuperuser = (user) => {
  const username = (user?.username || user?.email || '').toString().trim().toLowerCase();
  const userId = user?.userId;

  const ids = (process.env.SUPERUSER_USER_IDS || '')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean)
    .map((x) => parseInt(x, 10))
    .filter((x) => Number.isFinite(x));

  const names = (process.env.SUPERUSER_USERNAMES || '')
    .split(',')
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean);

  const uidNum = Number(userId);
  const byId = Number.isFinite(uidNum) && ids.includes(uidNum);
  const byName = username && names.includes(username);
  return Boolean(byId || byName);
};

// Утилита: доступ к отчётам и учёту занятий по списку имён в env (как суперпользователь)
// - PRIVATE_ACCESS_USERNAMES="teacher@example.com,admin"
// - PRIVATE_ACCESS_USER_IDS="1,2,3"
export const hasPrivateAccess = (user) => {
  const username = (user?.username || user?.email || '').toString().trim().toLowerCase();
  const userId = user?.userId;

  const ids = (process.env.PRIVATE_ACCESS_USER_IDS || '')
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean)
    .map((x) => parseInt(x, 10))
    .filter((x) => Number.isFinite(x));

  const names = (process.env.PRIVATE_ACCESS_USERNAMES || '')
    .split(',')
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean);

  const uidNum = Number(userId);
  const byId = Number.isFinite(uidNum) && ids.includes(uidNum);
  const byName = username && names.includes(username);
  return Boolean(byId || byName);
};

// Middleware: доступ только суперпользователю (для бухгалтерии/админки)
// Настройка через env:
// - SUPERUSER_USERNAMES="admin,owner@example" (логины из users.email; сравнение case-insensitive)
// - SUPERUSER_USER_IDS="1,2,3"
export const requireSuperuser = (req, res, next) => {
  if (isSuperuser(req.user)) return next();
  return res.status(403).json({ message: 'Требуется доступ суперпользователя' });
};

// Проверка токена для WebSocket
export const verifyWebSocketToken = (token, { allowAccessTokenFallback = true } = {}) => {
  try {
    if (!JWT_SECRET) return null;
    const payload = jwt.verify(token, JWT_SECRET, { algorithms: ['HS256'] });
    if (payload?.purpose === 'ws') return payload;
    if (allowAccessTokenFallback) return payload;
    return null;
  } catch (err) {
    return null;
  }
};

export const getWebSocketTokenTtlSeconds = () => SAFE_WS_TOKEN_TTL_SECONDS;

export const generateRefreshToken = (sessionId, userId, username, tokenVersion = 0) => {
  if (!REFRESH_JWT_SECRET) {
    throw new Error('JWT_REFRESH_SECRET не настроен на сервере');
  }
  return jwt.sign(
    {
      sid: sessionId,
      userId,
      email: username,
      username,
      tv: tokenVersion,
      purpose: 'refresh',
    },
    REFRESH_JWT_SECRET,
    { expiresIn: `${REFRESH_TOKEN_TTL_DAYS}d`, algorithm: 'HS256' }
  );
};

export const verifyRefreshToken = (token) => {
  try {
    if (!REFRESH_JWT_SECRET) return null;
    const payload = jwt.verify(token, REFRESH_JWT_SECRET, { algorithms: ['HS256'] });
    if (payload?.purpose !== 'refresh') return null;
    return payload;
  } catch (_) {
    return null;
  }
};

export const getRefreshTokenTtlDays = () => REFRESH_TOKEN_TTL_DAYS;

