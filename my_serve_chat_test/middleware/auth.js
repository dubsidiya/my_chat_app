import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';

// Middleware для проверки JWT токена
export const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  console.log(`🔐 Auth check: ${req.method} ${req.path}`);
  console.log(`   Authorization header: ${authHeader ? 'present' : 'missing'}`);
  console.log(`   Token: ${token ? token.substring(0, 20) + '...' : 'missing'}`);

  if (!token) {
    console.log('❌ No token provided');
    return res.status(401).json({ message: 'Токен доступа отсутствует' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      console.error('JWT verification error:', err.message);
      return res.status(403).json({ message: 'Недействительный токен' });
    }
    
    req.user = user; // Сохраняем данные пользователя в запросе
    req.userId = user.userId; // Добавляем userId для удобства
    // Нормализуем флаг приватного доступа (для старых токенов)
    req.user.privateAccess = user.privateAccess === true;
    // email в токене теперь содержит логин
    console.log(`✅ JWT verified: userId=${user.userId}, username=${user.email || user.username}`);
    next();
  });
};

// Генерация JWT токена
// username - логин пользователя (хранится в поле email в БД для обратной совместимости)
export const generateToken = (userId, username, privateAccess = false) => {
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
    return jwt.verify(token, JWT_SECRET);
  } catch (err) {
    return null;
  }
};

