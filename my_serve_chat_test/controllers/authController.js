import pool from '../db.js';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { generateToken } from '../middleware/auth.js';
import { validateRegisterData, validateLoginData, validatePassword } from '../utils/validation.js';
import { isSuperuser, hasPrivateAccess } from '../middleware/auth.js';

const PRIVATE_ACCESS_CODE = process.env.PRIVATE_ACCESS_CODE;

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
    console.log('Валидация не прошла:', { username: normalizedUsername, error: validation.message });
    return res.status(400).json({ message: validation.message });
  }

  try {
    // Проверяем существование пользователя с нормализованным логином
    // Используем LOWER и TRIM для поиска, чтобы найти даже если есть пробелы или другой регистр
    // Используем поле email в БД для хранения логина (для обратной совместимости)
    const existing = await pool.query(
      'SELECT id, email FROM users WHERE LOWER(TRIM(email)) = $1',
      [normalizedUsername]
    );
    
    if (existing.rows.length > 0) {
      console.log('Попытка регистрации существующего пользователя:', {
        requested: normalizedUsername,
        existing: existing.rows[0].email
      });
      return res.status(400).json({ message: 'Пользователь уже существует' });
    }

    // Хешируем пароль
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(password, saltRounds);

    const result = await pool.query(
      'INSERT INTO users (email, password) VALUES ($1, $2) RETURNING id, email, display_name',
      [normalizedUsername, hashedPassword]
    );

    const newUser = result.rows[0];
    const privateAccess = hasPrivateAccess({ userId: newUser.id, username: newUser.email });

    // Генерируем JWT токен (логин = email)
    const token = generateToken(newUser.id, newUser.email, privateAccess);

    res.status(201).json({
      userId: newUser.id,
      username: newUser.email,
      token: token,
      privateAccess,
      displayName: newUser.display_name ?? null,
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
    const result = await pool.query(
      'SELECT id, email, password, display_name FROM users WHERE LOWER(TRIM(email)) = $1',
      [normalizedUsername]
    );

    if (result.rows.length === 0) {
      // Не раскрываем, существует ли пользователь (защита от перечисления)
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
      return res.status(401).json({ message: 'Неверный логин или пароль' });
    }

    // Доступ к отчётам/учёту занятий: по списку в env или по коду (unlock-private)
    const privateAccess = hasPrivateAccess({ userId: user.id, username: user.email });

    // Генерируем JWT токен (используем логин вместо email)
    const token = generateToken(user.id, user.email, privateAccess);

    // Удаляем пароль из ответа
    delete user.password;

    res.status(200).json({
      id: user.id,
      username: user.email,
      token: token,
      isSuperuser: isSuperuser({ userId: user.id, username: user.email }),
      privateAccess,
      displayName: user.display_name ?? null,
    });
  } catch (error) {
    console.error('Ошибка входа:', error.message);
    res.status(500).json({ message: 'Ошибка сервера' });
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
    await pool.query('UPDATE users SET password = $1 WHERE id = $2', [hashedPassword, targetUserId]);
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
    const row = await pool.query(
      'SELECT id, email, display_name FROM users WHERE id = $1',
      [req.user.userId]
    );
    const u = row.rows[0];
    if (!u) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    res.status(200).json({
      id: u.id,
      username: u.email,
      displayName: u.display_name ?? null,
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
    const displayName = (req.body?.display_name ?? req.body?.displayName ?? '').toString().trim();
    if (displayName.length > 255) {
      return res.status(400).json({ message: 'Ник не более 255 символов' });
    }
    await pool.query(
      'UPDATE users SET display_name = $1 WHERE id = $2',
      [displayName || null, req.user.userId]
    );
    res.status(200).json({
      displayName: displayName || null,
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

    // Берем username из токена (email/username уже содержит логин)
    const username = req.user.username || req.user.email;
    const token = generateToken(req.user.userId, username, true);

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
    if (!fcmToken || typeof fcmToken !== 'string') {
      return res.status(400).json({ message: 'Укажите fcmToken в теле запроса' });
    }
    const tokenTrimmed = fcmToken.trim();
    if (!tokenTrimmed) {
      return res.status(400).json({ message: 'fcmToken не может быть пустым' });
    }
    await pool.query(
      'UPDATE users SET fcm_token = $1 WHERE id = $2',
      [tokenTrimmed, userId]
    );
    res.status(200).json({ message: 'Токен сохранён' });
  } catch (error) {
    console.error('Ошибка saveFcmToken:', error);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Получение списка всех пользователей (требует аутентификации)
export const getAllUsers = async (req, res) => {
  try {
    // req.user устанавливается middleware authenticateToken
    const currentUserId = req.user?.userId;
    
    if (!currentUserId) {
      return res.status(401).json({ message: 'Требуется аутентификация' });
    }

    const result = await pool.query(
      'SELECT id, email, display_name FROM users WHERE id != $1 ORDER BY COALESCE(display_name, email)',
      [currentUserId]
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

    // Начинаем транзакцию для безопасного удаления всех связанных данных
    const client = await pool.connect();
    
    try {
      await client.query('BEGIN'); // Начало транзакции

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

      // 5. Удаляем самого пользователя
      await client.query('DELETE FROM users WHERE id = $1', [userId]);
      console.log(`Удален пользователь ${userId}`);

      await client.query('COMMIT'); // Подтверждаем транзакцию
      
      res.status(200).json({ 
        message: 'Аккаунт успешно удален',
        deletedChats: createdChats.rows.length
      });

    } catch (error) {
      await client.query('ROLLBACK'); // Откатываем транзакцию при ошибке
      throw error;
    } finally {
      client.release(); // Освобождаем соединение
    }

  } catch (error) {
    console.error('Ошибка удаления аккаунта:', error);
    console.error('Stack:', error.stack);
    res.status(500).json({ 
      message: 'Ошибка удаления аккаунта',
      error: error.message 
    });
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

    // Хешируем новый пароль
    const saltRounds = 10;
    const hashedNewPassword = await bcrypt.hash(newPassword, saltRounds);

    // Обновляем пароль
    await pool.query(
      'UPDATE users SET password = $1 WHERE id = $2',
      [hashedNewPassword, userId]
    );

    console.log(`Пароль изменен для пользователя ${userId}`);

    res.status(200).json({ 
      message: 'Пароль успешно изменен'
    });

  } catch (error) {
    console.error('Ошибка смены пароля:', error);
    console.error('Stack:', error.stack);
    res.status(500).json({ 
      message: 'Ошибка смены пароля',
      error: error.message 
    });
  }
};

