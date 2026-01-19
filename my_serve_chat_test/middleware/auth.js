import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET;

// Middleware для проверки JWT токена
export const authenticateToken = (req, res, next) => {
  if (!JWT_SECRET) {
    // Не можем безопасно проверять токены без секрета
    return res.status(500).json({ message: 'JWT_SECRET не настроен на сервере' });
  }

  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

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

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      if (process.env.NODE_ENV === 'development') {
        console.error('JWT verification error:', err.message);
      }
      return res.status(403).json({ message: 'Недействительный токен' });
    }
    
    req.user = user; // Сохраняем данные пользователя в запросе
    req.userId = user.userId; // Добавляем userId для удобства
    // Нормализуем флаг приватного доступа (для старых токенов)
    req.user.privateAccess = user.privateAccess === true;
    // email в токене теперь содержит логин
    if (process.env.NODE_ENV === 'development') {
      console.log(`✅ JWT verified: userId=${user.userId}, username=${user.email || user.username}`);
    }
    next();
  });
};

// Генерация JWT токена
// username - логин пользователя (хранится в поле email в БД для обратной совместимости)
export const generateToken = (userId, username, privateAccess = false) => {
  if (!JWT_SECRET) {
    throw new Error('JWT_SECRET не настроен на сервере');
  }
  return jwt.sign(
    { userId, email: username, username: username, privateAccess: privateAccess === true },
    JWT_SECRET,
    { expiresIn: '7d' } // Токен действителен 7 дней
  );
};

// Middleware: доступ только к приватным разделам
export const requirePrivateAccess = (req, res, next) => {
  if (req.user?.privateAccess === true) {
    return next();
  }
  return res.status(403).json({ message: 'Требуется приватный доступ' });
};

// Проверка токена для WebSocket
export const verifyWebSocketToken = (token) => {
  try {
    if (!JWT_SECRET) return null;
    return jwt.verify(token, JWT_SECRET);
  } catch (err) {
    return null;
  }
};

