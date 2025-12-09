import pool from '../db.js';
export const register = async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ message: 'Email и пароль обязательны' });
  }

  try {
    const existing = await pool.query('SELECT 1 FROM users WHERE email = $1', [email]);
    if (existing.rows.length > 0) {
      return res.status(400).json({ message: 'Пользователь уже существует' });
    }

    const result = await pool.query(
      'INSERT INTO users (email, password) VALUES ($1, $2) RETURNING id, email',
      [email, password]
    );

    res.status(201).json({
      userId: result.rows[0].id,
      email: result.rows[0].email,
    });
  } catch (error) {
    console.error('Ошибка регистрации:', error.message);
    console.error(error.stack);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const login = async (req, res) => {
  const { email, password } = req.body;
  console.log('Login attempt:', { email, password });

  if (!email || !password) {
    return res.status(400).json({ message: 'Email и пароль обязательны' });
  }

  try {
    const result = await pool.query(
      'SELECT id, email FROM users WHERE email = $1 AND password = $2',
      [email, password]
    );
    console.log('DB query result:', result.rows);

    if (result.rows.length === 0) {
      return res.status(401).json({ message: 'Неверный email или пароль' });
    }

    res.status(200).json(result.rows[0]);
  } catch (error) {
    console.error('Ошибка входа:', error.message);
    res.status(500).json({ message: 'Ошибка сервера' });
  }
};

// Получение списка всех пользователей
export const getAllUsers = async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, email FROM users ORDER BY email'
    );
    res.json(result.rows);
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
    // Проверяем, существует ли пользователь и правильный ли пароль
    const userCheck = await pool.query(
      'SELECT id, email FROM users WHERE id = $1 AND password = $2',
      [userId, password]
    );

    if (userCheck.rows.length === 0) {
      return res.status(401).json({ message: 'Неверный пароль или пользователь не найден' });
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

