import pool from '../db.js';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import {
  generateToken,
  generateRefreshToken,
  generateWebSocketToken,
  getRefreshTokenTtlDays,
  getWebSocketTokenTtlSeconds,
  verifyRefreshToken,
} from '../middleware/auth.js';
import { validateRegisterData, validateLoginData, validatePassword } from '../utils/validation.js';
import { sanitizeForDisplay, parsePositiveInt } from '../utils/sanitize.js';
import { securityEvent } from '../utils/auditLog.js';
import { isSuperuser, hasPrivateAccess } from '../middleware/auth.js';
import { uploadToCloud } from '../utils/uploadImage.js';
import { DEFAULT_USER_TIMEZONE, normalizeTimeZone } from '../utils/timezone.js';
import { getSignedObjectUrl, toStorageKey } from '../utils/yandexStorage.js';
import { collectMessageMediaUrls, cleanupMessageMediaUrls } from '../utils/messageMediaCleanup.js';

const PRIVATE_ACCESS_CODE = process.env.PRIVATE_ACCESS_CODE;
let _authSessionsTableEnsured = false;

const toClientMediaUrl = async (value) => {
  const key = toStorageKey(value);
  if (!key) return value ?? null;
  return getSignedObjectUrl(key, 900);
};

const hashToken = (token) =>
  crypto.createHash('sha256').update(String(token || ''), 'utf8').digest('hex');

const getClientIp = (req) =>
  req?.ip || req?.get?.('x-forwarded-for')?.split(',')[0]?.trim() || req?.connection?.remoteAddress || null;

const ensureAuthSessionsTable = async () => {
  if (_authSessionsTableEnsured) return;
  await pool.query(`
    CREATE TABLE IF NOT EXISTS auth_sessions (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      refresh_token_hash TEXT NOT NULL,
      token_version INTEGER NOT NULL DEFAULT 0,
      user_agent TEXT NULL,
      ip TEXT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      expires_at TIMESTAMP NOT NULL,
      revoked_at TIMESTAMP NULL
    );
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_active
      ON auth_sessions(user_id, revoked_at, expires_at);
  `);
  _authSessionsTableEnsured = true;
};

const extractRefreshTokenFromRequest = (req) => {
  const fromBody = req.body?.refreshToken;
  const fromHeader = req.get?.('x-refresh-token');
  const cookieHeader = req.get?.('cookie') || '';
  let fromCookie = null;
  if (cookieHeader) {
    const parts = cookieHeader.split(';').map((x) => x.trim());
    const matched = parts.find((x) => x.startsWith('refresh_token='));
    if (matched) fromCookie = matched.slice('refresh_token='.length);
  }
  const token = (fromBody || fromHeader || fromCookie || '').toString().trim();
  return token || null;
};

const setRefreshCookieIfWeb = (req, res, refreshToken) => {
  const origin = (req.get?.('origin') || '').toString();
  const isBrowserRequest = origin.startsWith('http://') || origin.startsWith('https://');
  if (!isBrowserRequest) return;
  const maxAgeSeconds = getRefreshTokenTtlDays() * 24 * 60 * 60;
  const cookie = [
    `refresh_token=${refreshToken}`,
    'Path=/',
    'HttpOnly',
    'SameSite=Lax',
    req.secure ? 'Secure' : null,
    `Max-Age=${maxAgeSeconds}`,
  ]
    .filter(Boolean)
    .join('; ');
  res.setHeader('Set-Cookie', cookie);
};

const createUserSessionTokens = async (user, privateAccess, req) => {
  await ensureAuthSessionsTable();
  const sessionId = crypto.randomUUID();
  const tokenVersion = user.token_version ?? 0;
  const accessToken = generateToken(user.id, user.email, privateAccess, tokenVersion);
  const refreshToken = generateRefreshToken(sessionId, user.id, user.email, tokenVersion);
  const expiresAt = new Date(Date.now() + getRefreshTokenTtlDays() * 24 * 60 * 60 * 1000);
  await pool.query(
    `INSERT INTO auth_sessions (id, user_id, refresh_token_hash, token_version, user_agent, ip, expires_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [
      sessionId,
      user.id,
      hashToken(refreshToken),
      tokenVersion,
      req.get?.('user-agent') || null,
      getClientIp(req),
      expiresAt.toISOString(),
    ]
  );
  return { accessToken, refreshToken };
};
//
async function queryUserWithOptionalAvatarByEmail(normalizedUsername) {
  try {
    return await pool.query(
      'SELECT id, email, password, display_name, avatar_url, timezone, token_version FROM users WHERE LOWER(TRIM(email)) = $1',
      [normalizedUsername]
    );
  } catch (error) {
    if (error?.code === '42703' && String(error?.message || '').includes('token_version')) {
      const fallback = await pool.query(
        'SELECT id, email, password, display_name, avatar_url, timezone FROM users WHERE LOWER(TRIM(email)) = $1',
        [normalizedUsername]
      );
      fallback.rows = fallback.rows.map((r) => ({ ...r, token_version: 0 }));
      return fallback;
    }
    if (error?.code === '42703' && String(error?.message || '').includes('avatar_url')) {
      const fallback = await pool.query(
        'SELECT id, email, password, display_name FROM users WHERE LOWER(TRIM(email)) = $1',
        [normalizedUsername]
      );
      fallback.rows = fallback.rows.map((r) => ({ ...r, avatar_url: null, timezone: DEFAULT_USER_TIMEZONE, token_version: 0 }));
      return fallback;
    }
    if (error?.code === '42703' && String(error?.message || '').includes('timezone')) {
      const fallback = await pool.query(
        'SELECT id, email, password, display_name, avatar_url FROM users WHERE LOWER(TRIM(email)) = $1',
        [normalizedUsername]
      );
      fallback.rows = fallback.rows.map((r) => ({ ...r, timezone: DEFAULT_USER_TIMEZONE, token_version: 0 }));
      return fallback;
    }
    throw error;
  }
}

async function queryUserWithOptionalAvatarById(userId) {
  try {
    return await pool.query(
      'SELECT id, email, display_name, avatar_url, timezone, token_version FROM users WHERE id = $1',
      [userId]
    );
  } catch (error) {
    if (error?.code === '42703' && String(error?.message || '').includes('token_version')) {
      const fallback = await pool.query(
        'SELECT id, email, display_name, avatar_url, timezone FROM users WHERE id = $1',
        [userId]
      );
      fallback.rows = fallback.rows.map((r) => ({ ...r, token_version: 0 }));
      return fallback;
    }
    if (error?.code === '42703' && String(error?.message || '').includes('avatar_url')) {
      const fallback = await pool.query(
        'SELECT id, email, display_name FROM users WHERE id = $1',
        [userId]
      );
      fallback.rows = fallback.rows.map((r) => ({ ...r, avatar_url: null, timezone: DEFAULT_USER_TIMEZONE, token_version: 0 }));
      return fallback;
    }
    if (error?.code === '42703' && String(error?.message || '').includes('timezone')) {
      const fallback = await pool.query(
        'SELECT id, email, display_name, avatar_url FROM users WHERE id = $1',
        [userId]
      );
      fallback.rows = fallback.rows.map((r) => ({ ...r, timezone: DEFAULT_USER_TIMEZONE, token_version: 0 }));
      return fallback;
    }
    throw error;
  }
}

export const register = async (req, res) => {
  const { username, password } = req.body;

  // Проверяем наличие данных
  if (!username || !password) {
    return res.status(400).json({ message: 'Логин и пароль обязательны' });
  }

  // Нормализуем логин перед валидацией (убираем пробелы, приводим к нижнему регистру)
  const normalizedUsername = username.trim().toLowerCase();

  // Валидация данных
  const validation = validateRegisterData(normalizedUsername, password);
  if (!validation.valid) {
    if (process.env.NODE_ENV !== 'production') {
      console.log('Валидация регистрации не прошла:', { error: validation.message });
    }
    return res.status(400).json({ message: validation.message });
  }

  try {
    const timezoneFromHeader = normalizeTimeZone(req.headers['x-client-timezone']);
    const timezoneValue = timezoneFromHeader || DEFAULT_USER_TIMEZONE;
    // Проверяем существование пользователя с нормализованным логином
    // Используем LOWER и TRIM для поиска, чтобы найти даже если есть пробелы или другой регистр
    // Используем поле email в БД для хранения логина (для обратной совместимости)
    const existing = await pool.query(
      'SELECT id, email FROM users WHERE LOWER(TRIM(email)) = $1',
      [normalizedUsername]
    );
    
    if (existing.rows.length > 0) {
      if (process.env.NODE_ENV !== 'production') {
        console.log('Попытка регистрации существующего пользователя (логин не выводим в лог)');
      }
      return res.status(400).json({ message: 'Пользователь уже существует' });
    }

    // Хешируем пароль
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(password, saltRounds);

    const result = await pool.query(
      'INSERT INTO users (email, password, timezone) VALUES ($1, $2, $3) RETURNING id, email, display_name, timezone, token_version',
      [normalizedUsername, hashedPassword, timezoneValue]
    );

    const newUser = result.rows[0];
    const privateAccess = hasPrivateAccess({ userId: newUser.id, username: newUser.email });

    const { accessToken, refreshToken } = await createUserSessionTokens(newUser, privateAccess, req);
    setRefreshCookieIfWeb(req, res, refreshToken);

    res.status(201).json({
      userId: newUser.id,
      username: newUser.email,
      token: accessToken,
      refreshToken,
      privateAccess,
      displayName: newUser.display_name ?? null,
      timezone: newUser.timezone || DEFAULT_USER_TIMEZONE,
    });
  } catch (error) {
    console.error('Ошибка регистрации:', error.message);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const login = async (req, res) => {
  const { username, password } = req.body;
  
  // Проверяем наличие данных
  if (!username || !password) {
    return res.status(400).json({ message: 'Логин и пароль обязательны' });
  }
  
  // Валидация данных
  try {
    const validation = validateLoginData(username, password);
    if (!validation.valid) {
      return res.status(400).json({ message: validation.message });
    }
  } catch (error) {
    console.error('Ошибка валидации:', error);
    // Если validateLoginData не определена, продолжаем без валидации
    console.warn('validateLoginData не найдена, пропускаем валидацию');
  }

  try {
    // Нормализуем логин
    const normalizedUsername = username.toLowerCase().trim();
    
    // Получаем пользователя по логину (поле email = логин)
    const result = await queryUserWithOptionalAvatarByEmail(normalizedUsername);

    if (result.rows.length === 0) {
      securityEvent('login_fail', req);
      return res.status(401).json({ message: 'Неверный логин или пароль' });
    }

    const user = result.rows[0];
    
    // Проверяем, хеширован ли пароль (bcrypt хеши начинаются с $2)
    const isPasswordHashed = user.password && user.password.startsWith('$2');
    
    let passwordMatch = false;
    
    if (isPasswordHashed) {
      // Пароль уже хеширован - используем bcrypt.compare
      passwordMatch = await bcrypt.compare(password, user.password);
    } else {
      // Пароль в открытом виде - сравниваем напрямую (миграция на лету)
      passwordMatch = user.password === password;
      
      if (passwordMatch) {
        // Пароль совпал - перехешируем его
        console.log(`Миграция пароля для пользователя ${user.id}`);
        const hashedPassword = await bcrypt.hash(password, 10);
        await pool.query(
          'UPDATE users SET password = $1 WHERE id = $2',
          [hashedPassword, user.id]
        );
        console.log(`Пароль пользователя ${user.id} успешно перехеширован`);
      }
    }
    
    if (!passwordMatch) {
      securityEvent('login_fail', req);
      return res.status(401).json({ message: 'Неверный логин или пароль' });
    }

    const privateAccess = hasPrivateAccess({ userId: user.id, username: user.email });

    const { accessToken, refreshToken } = await createUserSessionTokens(user, privateAccess, req);
    setRefreshCookieIfWeb(req, res, refreshToken);

    delete user.password;

    res.status(200).json({
      id: user.id,
      username: user.email,
      token: accessToken,
      refreshToken,
      isSuperuser: isSuperuser({ userId: user.id, username: user.email }),
      privateAccess,
      displayName: user.display_name ?? null,
      avatarUrl: await toClientMediaUrl(user.avatar_url),
      timezone: normalizeTimeZone(user.timezone) || DEFAULT_USER_TIMEZONE,
    });
  } catch (error) {
    console.error('Ошибка входа:', error.message);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Короткоживущий токен только для WebSocket-подключения (особенно для web-клиента).
export const getWebSocketToken = async (req, res) => {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }

    const userRow = await pool.query(
      'SELECT id, email, token_version FROM users WHERE id = $1',
      [userId]
    );
    if (userRow.rows.length === 0) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    const user = userRow.rows[0];
    const wsToken = generateWebSocketToken(
      user.id,
      user.email,
      user.token_version ?? 0
    );
    return res.status(200).json({
      wsToken,
      expiresInSeconds: getWebSocketTokenTtlSeconds(),
    });
  } catch (error) {
    console.error('Ошибка getWebSocketToken:', error.message);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Обновление access-токена по refresh-токену.
export const refreshSession = async (req, res) => {
  try {
    const refreshToken = extractRefreshTokenFromRequest(req);
    if (!refreshToken) {
      return res.status(401).json({ message: 'Refresh токен отсутствует' });
    }
    const decoded = verifyRefreshToken(refreshToken);
    if (!decoded?.sid || !decoded?.userId) {
      return res.status(401).json({ message: 'Недействительный refresh токен' });
    }

    await ensureAuthSessionsTable();
    const session = await pool.query(
      `SELECT id, user_id, token_version, refresh_token_hash
       FROM auth_sessions
       WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL AND expires_at > CURRENT_TIMESTAMP
       LIMIT 1`,
      [decoded.sid, decoded.userId]
    );
    if (session.rows.length === 0) {
      return res.status(401).json({ message: 'Сессия недействительна' });
    }
    const row = session.rows[0];
    if (row.refresh_token_hash !== hashToken(refreshToken)) {
      await pool.query(
        'UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1',
        [row.id]
      );
      return res.status(401).json({ message: 'Сессия недействительна' });
    }

    const userResult = await queryUserWithOptionalAvatarById(decoded.userId);
    const user = userResult.rows[0];
    if (!user) {
      return res.status(401).json({ message: 'Пользователь не найден' });
    }
    const dbTokenVersion = user.token_version ?? 0;
    if ((decoded.tv ?? 0) !== dbTokenVersion || row.token_version !== dbTokenVersion) {
      await pool.query(
        'UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE id = $1',
        [row.id]
      );
      return res.status(401).json({ message: 'Сессия истекла. Пожалуйста, войдите заново' });
    }

    const privateAccess = hasPrivateAccess({ userId: user.id, username: user.email });
    const accessToken = generateToken(user.id, user.email, privateAccess, dbTokenVersion);
    const rotatedRefreshToken = generateRefreshToken(row.id, user.id, user.email, dbTokenVersion);
    const expiresAt = new Date(Date.now() + getRefreshTokenTtlDays() * 24 * 60 * 60 * 1000);
    await pool.query(
      `UPDATE auth_sessions
       SET refresh_token_hash = $2,
           token_version = $3,
           last_seen_at = CURRENT_TIMESTAMP,
           ip = $4,
           user_agent = $5,
           expires_at = $6
       WHERE id = $1`,
      [
        row.id,
        hashToken(rotatedRefreshToken),
        dbTokenVersion,
        getClientIp(req),
        req.get?.('user-agent') || null,
        expiresAt.toISOString(),
      ]
    );

    setRefreshCookieIfWeb(req, res, rotatedRefreshToken);
    return res.status(200).json({
      token: accessToken,
      refreshToken: rotatedRefreshToken,
      privateAccess,
      isSuperuser: isSuperuser({ userId: user.id, username: user.email }),
    });
  } catch (error) {
    console.error('Ошибка refreshSession:', error.message);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Logout: отзываем текущую refresh-сессию, если токен передан, иначе все сессии пользователя.
export const logout = async (req, res) => {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }
    await ensureAuthSessionsTable();

    const refreshToken = extractRefreshTokenFromRequest(req);
    if (refreshToken) {
      const decoded = verifyRefreshToken(refreshToken);
      if (decoded?.sid && decoded?.userId?.toString() === userId.toString()) {
        await pool.query(
          `UPDATE auth_sessions
           SET revoked_at = CURRENT_TIMESTAMP, last_seen_at = CURRENT_TIMESTAMP
           WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL`,
          [decoded.sid, userId]
        );
      } else {
        await pool.query(
          `UPDATE auth_sessions
           SET revoked_at = CURRENT_TIMESTAMP, last_seen_at = CURRENT_TIMESTAMP
           WHERE user_id = $1 AND revoked_at IS NULL`,
          [userId]
        );
      }
    } else {
      await pool.query(
        `UPDATE auth_sessions
         SET revoked_at = CURRENT_TIMESTAMP, last_seen_at = CURRENT_TIMESTAMP
         WHERE user_id = $1 AND revoked_at IS NULL`,
        [userId]
      );
    }

    res.setHeader('Set-Cookie', 'refresh_token=; Path=/; HttpOnly; Max-Age=0; SameSite=Lax');
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Ошибка logout:', error.message);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Сброс пароля пользователя (только суперпользователь)
export const adminResetUserPassword = async (req, res) => {
  const { username, newPassword } = req.body || {};
  const raw = (username || '').toString().trim().toLowerCase();
  if (!raw || raw.length > 255) {
    return res.status(400).json({ message: 'Укажите логин пользователя' });
  }
  const passwordValidation = validatePassword(newPassword);
  if (!passwordValidation.valid) {
    return res.status(400).json({ message: passwordValidation.message });
  }
  try {
    const userResult = await pool.query(
      'SELECT id, email FROM users WHERE LOWER(TRIM(email)) = $1',
      [raw]
    );
    if (userResult.rows.length === 0) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    const targetUserId = userResult.rows[0].id;
    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await pool.query(
      'UPDATE users SET password = $1, token_version = token_version + 1 WHERE id = $2',
      [hashedPassword, targetUserId]
    );
    securityEvent('admin_reset_password', req, { targetUserId });
    return res.status(200).json({ message: 'Пароль успешно изменён' });
  } catch (error) {
    console.error('Ошибка adminResetUserPassword:', error.message);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Текущий пользователь (логин, ник, права)
export const getMe = async (req, res) => {
  try {
    if (!req.user?.userId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }
    const row = await queryUserWithOptionalAvatarById(req.user.userId);
    const u = row.rows[0];
    if (!u) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    res.status(200).json({
      id: u.id,
      username: u.email,
      displayName: u.display_name ?? null,
      avatarUrl: await toClientMediaUrl(u.avatar_url),
      timezone: normalizeTimeZone(u.timezone) || DEFAULT_USER_TIMEZONE,
      isSuperuser: isSuperuser(req.user),
      privateAccess: req.user.privateAccess === true,
    });
  } catch (error) {
    console.error('Ошибка getMe:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Обновление ника (как тебя видят другие). Логин не меняется.
export const updateProfile = async (req, res) => {
  try {
    if (!req.user?.userId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }
    const raw = (req.body?.display_name ?? req.body?.displayName ?? '').toString();
    const displayName = sanitizeForDisplay(raw, 255);
    const rawTimezone = req.body?.timezone;
    const timezone = rawTimezone == null || String(rawTimezone).trim() === ''
      ? null
      : normalizeTimeZone(rawTimezone);
    if (rawTimezone != null && timezone == null) {
      return res.status(400).json({ message: 'Некорректная timezone (ожидается IANA, например Europe/Moscow)' });
    }
    await pool.query(
      timezone
        ? 'UPDATE users SET display_name = $1, timezone = $2 WHERE id = $3'
        : 'UPDATE users SET display_name = $1 WHERE id = $2',
      timezone
        ? [displayName || null, timezone, req.user.userId]
        : [displayName || null, req.user.userId]
    );
    res.status(200).json({
      displayName: displayName || null,
      timezone: timezone || undefined,
    });
  } catch (error) {
    console.error('Ошибка updateProfile:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Разблокировка приватного доступа (выдача токена с privateAccess=true)
export const unlockPrivateAccess = async (req, res) => {
  try {
    if (!req.user?.userId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }

    if (!PRIVATE_ACCESS_CODE) {
      return res.status(500).json({
        message: 'PRIVATE_ACCESS_CODE не настроен на сервере',
      });
    }

    const { code } = req.body || {};
    if (!code || typeof code !== 'string') {
      return res.status(400).json({ message: 'Код обязателен' });
    }

    const normalized = code.trim();
    // Сравнение в константное время (защита от тайминг-атак)
    const a = Buffer.from(normalized, 'utf8');
    const b = Buffer.from(PRIVATE_ACCESS_CODE, 'utf8');
    const isEqual = a.length === b.length && crypto.timingSafeEqual(a, b);
    if (!isEqual) {
      // Не логируем userId/ip в продакшене (избегаем утечек PII в логах)
      if (process.env.NODE_ENV === 'development') {
        console.warn('unlockPrivateAccess: wrong code');
      }
      return res.status(403).json({ message: 'Неверный код' });
    }

    const username = req.user.username || req.user.email;
    const tvRow = await pool.query('SELECT token_version FROM users WHERE id = $1', [req.user.userId]);
    const tv = tvRow.rows[0]?.token_version ?? 0;
    const token = generateToken(req.user.userId, username, true, tv);

    return res.status(200).json({
      id: req.user.userId,
      username: username,
      token: token,
      privateAccess: true,
    });
  } catch (error) {
    console.error('Ошибка unlockPrivateAccess:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Сохранение FCM-токена для push-уведомлений (требует аутентификации)
export const saveFcmToken = async (req, res) => {
  try {
    const userId = req.user?.userId;
    if (!userId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }
    const { fcmToken } = req.body || {};
    if (fcmToken === undefined || fcmToken === null) {
      return res.status(400).json({ message: 'Укажите fcmToken в теле запроса' });
    }
    const tokenTrimmed = typeof fcmToken === 'string' ? fcmToken.trim() : '';
    if (tokenTrimmed.length > 0) {
      const FCM_TOKEN_MAX_LENGTH = 1024;
      if (tokenTrimmed.length > FCM_TOKEN_MAX_LENGTH) {
        return res.status(400).json({ message: `fcmToken не более ${FCM_TOKEN_MAX_LENGTH} символов` });
      }
      await pool.query(
        'UPDATE users SET fcm_token = $1 WHERE id = $2',
        [tokenTrimmed, userId]
      );
      // Не логируем токен (секрет/PII). Только факт и длина.
      console.log('FCM token saved:', { userId, length: tokenTrimmed.length });
      return res.status(200).json({ message: 'Токен сохранён' });
    }
    // Пустая строка — сброс токена (при выходе из аккаунта)
    await pool.query(
      'UPDATE users SET fcm_token = NULL WHERE id = $1',
      [userId]
    );
    console.log('FCM token cleared:', { userId });
    res.status(200).json({ message: 'Токен сброшен' });
  } catch (error) {
    console.error('Ошибка saveFcmToken:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Загрузка аватара (multipart/form-data, поле avatar)
export const uploadAvatar = async (req, res) => {
  try {
    if (!req.user?.userId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }
    if (!req.file || !req.file.buffer) {
      return res.status(400).json({ message: 'Выберите изображение для аватара' });
    }
    const { imageUrl, objectKey } = await uploadToCloud(req.file, 'avatars');
    try {
      await pool.query(
        'UPDATE users SET avatar_url = $1 WHERE id = $2',
        [objectKey || imageUrl, req.user.userId]
      );
    } catch (error) {
      if (error?.code === '42703' && String(error?.message || '').includes('avatar_url')) {
        return res.status(500).json({
          message: 'База данных не обновлена: отсутствует колонка avatar_url. Примените миграцию migrations/add_avatar_url.sql',
        });
      }
      throw error;
    }
    res.status(200).json({ avatarUrl: imageUrl });
  } catch (error) {
    console.error('Ошибка uploadAvatar:', error);
    res.status(500).json({ message: 'Ошибка загрузки аватара' });
  }
};

// Профиль пользователя (аватар/ник). Доступен только если запрашивающий
// состоит хотя бы в одном общем чате с целевым пользователем — защита от перебора userId.
export const getUserById = async (req, res) => {
  try {
    const targetId = parsePositiveInt(req.params?.userId);
    if (!targetId) return res.status(404).json({ message: 'Пользователь не найден' });

    const currentUserId = req.user?.userId;
    if (!currentUserId) return res.status(401).json({ message: 'Требуется аутентификация' });

    if (targetId === currentUserId) {
      const row = await queryUserWithOptionalAvatarById(targetId);
      const u = row.rows[0];
      if (!u) return res.status(404).json({ message: 'Пользователь не найден' });
      return res.status(200).json({
        id: u.id,
        username: u.email,
        displayName: u.display_name ?? null,
        avatarUrl: await toClientMediaUrl(u.avatar_url),
      });
    }

    const sharedChat = await pool.query(
      `SELECT 1 FROM chat_users a
       JOIN chat_users b ON a.chat_id = b.chat_id
       WHERE a.user_id = $1 AND b.user_id = $2
       LIMIT 1`,
      [currentUserId, targetId]
    );
    if (sharedChat.rows.length === 0) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }

    const row = await queryUserWithOptionalAvatarById(targetId);
    const u = row.rows[0];
    if (!u) return res.status(404).json({ message: 'Пользователь не найден' });

    return res.status(200).json({
      id: u.id,
      username: u.email,
      displayName: u.display_name ?? null,
      avatarUrl: await toClientMediaUrl(u.avatar_url),
    });
  } catch (error) {
    console.error('Ошибка getUserById:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Список пользователей для создания чатов. Возвращает минимум полей (id, ник).
// Защита от перебора — на уровне getUserById (там проверка общих чатов).
export const getAllUsers = async (req, res) => {
  try {
    const currentUserId = req.user?.userId;
    
    if (!currentUserId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }

    const qRaw = (req.query?.q || '').toString().trim().toLowerCase();
    const limitRaw = parseInt(req.query?.limit, 10);
    const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(limitRaw, 1), 20) : 20;
    if (qRaw.length < 2) {
      return res.json([]);
    }

    const result = await pool.query(
      `SELECT u.id, u.email, u.display_name
       FROM users u
       WHERE u.id != $1
         AND (
           LOWER(u.email) LIKE $2
           OR LOWER(COALESCE(u.display_name, '')) LIKE $2
         )
       ORDER BY COALESCE(NULLIF(TRIM(u.display_name), ''), u.email)
       LIMIT $3`,
      [currentUserId, `%${qRaw}%`, limit]
    );
    res.json(result.rows.map((r) => ({
      id: r.id,
      email: r.email,
      display_name: r.display_name ?? null,
    })));
  } catch (error) {
    console.error('Ошибка получения пользователей:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Удаление аккаунта пользователя
export const deleteAccount = async (req, res) => {
  const userId = req.params.userId;
  const password = req.body.password; // Требуем пароль для подтверждения

  if (!userId) {
    return res.status(400).json({ message: 'Укажите ID пользователя' });
  }

  if (!password) {
    return res.status(400).json({ message: 'Для удаления аккаунта требуется пароль' });
  }

  try {
    // Проверяем права доступа (только владелец может удалить свой аккаунт)
    const currentUserId = req.user?.userId;
    if (currentUserId && currentUserId.toString() !== userId.toString()) {
      return res.status(403).json({ message: 'Вы можете удалить только свой аккаунт' });
    }

    // Получаем пользователя
    const userCheck = await pool.query(
      'SELECT id, email, password FROM users WHERE id = $1',
      [userId]
    );

    if (userCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }

    // Проверяем пароль
    const passwordMatch = await bcrypt.compare(password, userCheck.rows[0].password);
    if (!passwordMatch) {
      return res.status(401).json({ message: 'Неверный пароль' });
    }

    const client = await pool.connect();
    let mediaUrlsToCleanup = [];
    try {
      try { await client.query('ROLLBACK'); } catch (_) {}
      await client.query('BEGIN');

      // Собираем ссылки на медиа заранее, чтобы после коммита очистить Object Storage.
      const ownMediaRows = await client.query(
        `SELECT image_url, original_image_url, file_url
         FROM messages
         WHERE user_id = $1`,
        [userId]
      );
      mediaUrlsToCleanup = collectMessageMediaUrls(ownMediaRows.rows);

      // 1. Удаляем все сообщения пользователя
      await client.query('DELETE FROM messages WHERE user_id = $1', [userId]);
      console.log(`Удалены сообщения пользователя ${userId}`);

      // 2. Получаем чаты, где пользователь является создателем
      const createdChats = await client.query(
        'SELECT id FROM chats WHERE created_by = $1',
        [userId]
      );

      // 3. Для каждого чата, где пользователь создатель - удаляем чат полностью
      for (const chat of createdChats.rows) {
        const chatId = chat.id;
        const chatMediaRows = await client.query(
          `SELECT image_url, original_image_url, file_url
           FROM messages
           WHERE chat_id = $1`,
          [chatId]
        );
        mediaUrlsToCleanup = [
          ...mediaUrlsToCleanup,
          ...collectMessageMediaUrls(chatMediaRows.rows),
        ];
        // Удаляем сообщения чата
        await client.query('DELETE FROM messages WHERE chat_id = $1', [chatId]);
        // Удаляем участников чата
        await client.query('DELETE FROM chat_users WHERE chat_id = $1', [chatId]);
        // Удаляем сам чат
        await client.query('DELETE FROM chats WHERE id = $1', [chatId]);
        console.log(`Удален чат ${chatId}, созданный пользователем ${userId}`);
      }

      // 4. Удаляем пользователя из всех чатов (где он участник, но не создатель)
      await client.query('DELETE FROM chat_users WHERE user_id = $1', [userId]);
      console.log(`Удалено участие пользователя ${userId} в чатах`);

      // 5. Инвалидируем все токены перед удалением
      await client.query('UPDATE users SET token_version = token_version + 1 WHERE id = $1', [userId]);

      // 6. Удаляем самого пользователя
      await client.query('DELETE FROM users WHERE id = $1', [userId]);
      console.log(`Удален пользователь ${userId}`);

      await client.query('COMMIT'); // Подтверждаем транзакцию
      const cleanupResult = await cleanupMessageMediaUrls(mediaUrlsToCleanup, {
        label: 'deleteAccount',
      });
      if (cleanupResult.attempted > 0) {
        console.log(`deleteAccount: cleanup attempted for ${cleanupResult.attempted} media objects (user ${userId})`);
      }
      securityEvent('account_deleted', req);
      res.status(200).json({
        message: 'Аккаунт успешно удален',
        deletedChats: createdChats.rows.length
      });

    } catch (error) {
      try { await client.query('ROLLBACK'); } catch (_) {}
      throw error;
    } finally {
      try { await client.query('ROLLBACK'); } catch (_) {}
      client.release();
    }

  } catch (error) {
    console.error('Ошибка удаления аккаунта:', error);
    if (process.env.NODE_ENV !== 'production') {
      console.error('Stack:', error.stack);
    }
    res.status(500).json({ message: 'Ошибка удаления аккаунта' });
  }
};

// Смена пароля пользователя
export const changePassword = async (req, res) => {
  const userId = req.params.userId;
  const { oldPassword, newPassword } = req.body;

  if (!userId) {
    return res.status(400).json({ message: 'Укажите ID пользователя' });
  }

  if (!oldPassword || !newPassword) {
    return res.status(400).json({ message: 'Требуются старый и новый пароль' });
  }

  if (oldPassword === newPassword) {
    return res.status(400).json({ message: 'Новый пароль должен отличаться от старого' });
  }


  try {
    // Проверяем права доступа (только владелец может изменить пароль)
    const currentUserId = req.user?.userId;
    if (currentUserId && currentUserId.toString() !== userId.toString()) {
      return res.status(403).json({ message: 'Вы можете изменить только свой пароль' });
    }

    // Валидация нового пароля
    const passwordValidation = validatePassword(newPassword);
    if (!passwordValidation.valid) {
      return res.status(400).json({ message: passwordValidation.message });
    }

    // Получаем пользователя
    const userCheck = await pool.query(
      'SELECT id, email, password FROM users WHERE id = $1',
      [userId]
    );

    if (userCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }

    // Проверяем старый пароль
    const passwordMatch = await bcrypt.compare(oldPassword, userCheck.rows[0].password);
    if (!passwordMatch) {
      return res.status(401).json({ message: 'Неверный текущий пароль' });
    }

    const saltRounds = 10;
    const hashedNewPassword = await bcrypt.hash(newPassword, saltRounds);

    const updateResult = await pool.query(
      'UPDATE users SET password = $1, token_version = token_version + 1 WHERE id = $2 RETURNING email, token_version',
      [hashedNewPassword, userId]
    );

    const updatedUser = updateResult.rows[0];
    const privateAccess = hasPrivateAccess({ userId: parseInt(userId, 10), username: updatedUser.email });
    await ensureAuthSessionsTable();
    await pool.query(
      'UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND revoked_at IS NULL',
      [userId]
    );
    const rotated = await createUserSessionTokens(
      { id: parseInt(userId, 10), email: updatedUser.email, token_version: updatedUser.token_version },
      privateAccess,
      req
    );
    const newToken = rotated.accessToken;
    setRefreshCookieIfWeb(req, res, rotated.refreshToken);

    console.log(`Пароль изменен для пользователя ${userId}`);

    securityEvent('password_changed', req);
    res.status(200).json({
      message: 'Пароль успешно изменен',
      token: newToken,
      refreshToken: rotated.refreshToken,
    });
  } catch (error) {
    console.error('Ошибка смены пароля:', error);
    if (process.env.NODE_ENV !== 'production') {
      console.error('Stack:', error.stack);
    }
    res.status(500).json({ message: 'Ошибка смены пароля' });
  }
};

