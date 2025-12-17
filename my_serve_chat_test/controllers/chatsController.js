import pool from '../db.js';

// Получение всех чатов пользователя
export const getUserChats = async (req, res) => {
  try {
    // Используем userId из токена (безопасно)
    const userId = req.user.userId;

    // Используем chat_users (как в схеме БД) вместо chat_members
    const result = await pool.query(
      `SELECT c.id, c.name, c.is_group
       FROM chats c
       JOIN chat_users cu ON c.id = cu.chat_id
       WHERE cu.user_id = $1`,
      [userId]
    );

    res.json(result.rows);
  } catch (error) {
    console.error("Ошибка getUserChats:", error);
    res.status(500).json({ message: "Ошибка получения чатов" });
  }
};

// Создание чата
export const createChat = async (req, res) => {
  try {
    // Приложение отправляет: { name, userIds: [userId1, userId2, ...] }
    const { name, userIds } = req.body;

    if (!name) {
      return res.status(400).json({ message: "Укажите имя чата" });
    }

    if (!Array.isArray(userIds) || userIds.length === 0) {
      return res.status(400).json({ message: "Укажите хотя бы одного участника (userIds)" });
    }

    // Определяем, групповой ли чат (больше 1 участника)
    const isGroup = userIds.length > 1;

    // Создатель чата - текущий пользователь из токена
    const creatorId = req.user.userId;
    
    // Добавляем создателя в список участников, если его там нет
    if (!userIds.includes(creatorId.toString())) {
      userIds.unshift(creatorId.toString());
    }

    // Создаём чат с is_group и created_by
    const chatResult = await pool.query(
      `INSERT INTO chats (name, is_group, created_by) VALUES ($1, $2, $3) RETURNING id, name, is_group, created_by`,
      [name, isGroup, creatorId]
    );

    const chatId = chatResult.rows[0].id;

    // Добавляем участников в chat_users (как в схеме БД)
    for (const userId of userIds) {
      await pool.query(
        `INSERT INTO chat_users (chat_id, user_id) VALUES ($1, $2)`,
        [chatId, userId]
      );
    }

    // Возвращаем 201 (Created) как ожидает приложение
    res.status(201).json({
      id: chatId,
      name: chatResult.rows[0].name,
      is_group: chatResult.rows[0].is_group
    });

  } catch (error) {
    console.error("Ошибка createChat:", error);
    res.status(500).json({ message: "Ошибка создания чата" });
  }
};

// Удаление чата
export const deleteChat = async (req, res) => {
  try {
    const chatId = req.params.id;
    // userId берем из токена (безопасно)
    const userId = req.user.userId;

    if (!chatId) {
      return res.status(400).json({ message: "Укажите ID чата" });
    }

    // Проверяем, существует ли чат
    const chatCheck = await pool.query(
      'SELECT id, created_by FROM chats WHERE id = $1',
      [chatId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(404).json({ message: "Чат не найден" });
    }

    const chat = chatCheck.rows[0];
    const creatorId = chat.created_by;

    // Проверяем, является ли пользователь создателем
    const userIdStr = userId.toString();
    const creatorIdStr = creatorId?.toString();
    
    if (creatorIdStr && userIdStr !== creatorIdStr) {
      return res.status(403).json({ 
        message: "Только создатель чата может его удалить" 
      });
    }

    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ 
        message: "Вы не являетесь участником этого чата" 
      });
    }

    // Удаляем все сообщения чата (если CASCADE не работает)
    try {
      await pool.query('DELETE FROM messages WHERE chat_id = $1', [chatId]);
    } catch (msgError) {
      console.error('Ошибка удаления сообщений:', msgError);
      // Продолжаем, даже если не удалось удалить сообщения
    }

    // Удаляем всех участников чата (если CASCADE не работает)
    try {
      await pool.query('DELETE FROM chat_users WHERE chat_id = $1', [chatId]);
    } catch (usersError) {
      console.error('Ошибка удаления участников:', usersError);
      // Продолжаем, даже если не удалось удалить участников
    }

    // Удаляем чат
    await pool.query('DELETE FROM chats WHERE id = $1', [chatId]);

    res.status(200).json({ message: "Чат успешно удален" });

  } catch (error) {
    console.error("Ошибка deleteChat:", error);
    console.error("Stack:", error.stack);
    res.status(500).json({ 
      message: "Ошибка удаления чата",
      error: error.message 
    });
  }
};

// Получение участников чата
export const getChatMembers = async (req, res) => {
  try {
    const chatId = req.params.id;

    // Получаем информацию о чате, включая создателя
    const chatInfo = await pool.query(
      'SELECT created_by FROM chats WHERE id = $1',
      [chatId]
    );

    if (chatInfo.rows.length === 0) {
      return res.status(404).json({ message: "Чат не найден" });
    }

    const creatorId = chatInfo.rows[0].created_by;

    // Получаем участников чата
    const result = await pool.query(
      `SELECT u.id, u.email
       FROM users u
       JOIN chat_users cu ON u.id = cu.user_id
       WHERE cu.chat_id = $1
       ORDER BY u.id`,
      [chatId]
    );

    // Добавляем информацию о том, кто создатель
    const members = result.rows.map(row => ({
      id: row.id,
      email: row.email,
      is_creator: row.id === creatorId
    }));

    res.json(members);
  } catch (error) {
    console.error("Ошибка getChatMembers:", error);
    res.status(500).json({ message: "Ошибка получения участников чата" });
  }
};

// Добавление участников в чат
export const addMembersToChat = async (req, res) => {
  try {
    const chatId = req.params.id;
    const { userIds } = req.body;

    if (!Array.isArray(userIds) || userIds.length === 0) {
      return res.status(400).json({ message: "Укажите хотя бы одного участника (userIds)" });
    }

    // Проверяем, существует ли чат
    const chatCheck = await pool.query(
      'SELECT id FROM chats WHERE id = $1',
      [chatId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(404).json({ message: "Чат не найден" });
    }

    // Добавляем участников (пропускаем, если уже есть)
    const addedUsers = [];
    for (const userId of userIds) {
      try {
        // Проверяем, не является ли пользователь уже участником
        const existing = await pool.query(
          'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
          [chatId, userId]
        );

        if (existing.rows.length === 0) {
          await pool.query(
            `INSERT INTO chat_users (chat_id, user_id) VALUES ($1, $2)`,
            [chatId, userId]
          );
          addedUsers.push(userId);
        }
      } catch (e) {
        console.error(`Ошибка при добавлении пользователя ${userId}:`, e);
        // Продолжаем добавлять остальных
      }
    }

    // Обновляем is_group, если участников стало больше 1
    const memberCount = await pool.query(
      'SELECT COUNT(*) as count FROM chat_users WHERE chat_id = $1',
      [chatId]
    );
    const count = parseInt(memberCount.rows[0].count);
    
    if (count > 1) {
      await pool.query(
        'UPDATE chats SET is_group = true WHERE id = $1',
        [chatId]
      );
    }

    res.status(200).json({
      message: "Участники успешно добавлены",
      addedCount: addedUsers.length
    });

  } catch (error) {
    console.error("Ошибка addMembersToChat:", error);
    res.status(500).json({ message: "Ошибка добавления участников" });
  }
};

// Удаление участника из чата
export const removeMemberFromChat = async (req, res) => {
  try {
    const chatId = req.params.id;
    const userId = req.params.userId; // Получаем из URL параметра

    if (!userId) {
      return res.status(400).json({ message: "Укажите ID пользователя" });
    }

    // Проверяем, существует ли чат
    const chatCheck = await pool.query(
      'SELECT id FROM chats WHERE id = $1',
      [chatId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(404).json({ message: "Чат не найден" });
    }

    // Получаем информацию о чате, включая создателя
    const chatInfo = await pool.query(
      'SELECT created_by FROM chats WHERE id = $1',
      [chatId]
    );

    if (chatInfo.rows.length === 0) {
      return res.status(404).json({ message: "Чат не найден" });
    }

    const creatorId = chatInfo.rows[0].created_by;

    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(404).json({ message: "Пользователь не является участником чата" });
    }

    // Не позволяем удалить создателя чата
    if (userId == creatorId || userId.toString() === creatorId?.toString()) {
      return res.status(400).json({ message: "Нельзя удалить создателя чата" });
    }

    // Получаем количество участников
    const memberCount = await pool.query(
      'SELECT COUNT(*) as count FROM chat_users WHERE chat_id = $1',
      [chatId]
    );
    const count = parseInt(memberCount.rows[0].count);

    // Не позволяем удалить последнего участника
    if (count <= 1) {
      return res.status(400).json({ message: "Нельзя удалить последнего участника чата" });
    }

    // Удаляем участника
    await pool.query(
      'DELETE FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );

    // Обновляем is_group, если участников стало 1 или меньше
    const newCount = await pool.query(
      'SELECT COUNT(*) as count FROM chat_users WHERE chat_id = $1',
      [chatId]
    );
    const newCountValue = parseInt(newCount.rows[0].count);
    
    if (newCountValue <= 1) {
      await pool.query(
        'UPDATE chats SET is_group = false WHERE id = $1',
        [chatId]
      );
    }

    res.status(200).json({ message: "Участник успешно удален из чата" });

  } catch (error) {
    console.error("Ошибка removeMemberFromChat:", error);
    res.status(500).json({ message: "Ошибка удаления участника" });
  }
};
