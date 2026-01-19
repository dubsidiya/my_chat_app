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

// Получение списка чатов пользователя с последним сообщением и непрочитанными
export const getChatsList = async (req, res) => {
  try {
    const userId = req.user.userId;

    const result = await pool.query(
      `
      WITH user_chats AS (
        SELECT c.id, c.name, c.is_group
        FROM chats c
        JOIN chat_users cu ON cu.chat_id = c.id
        WHERE cu.user_id = $1
      ),
      last_messages AS (
        SELECT DISTINCT ON (m.chat_id)
          m.chat_id,
          m.id AS last_message_id,
          m.content AS last_message_content,
          m.message_type AS last_message_type,
          m.image_url AS last_message_image_url,
          m.created_at AS last_message_created_at,
          u.email AS last_sender_email
        FROM messages m
        JOIN users u ON u.id = m.user_id
        JOIN user_chats uc ON uc.id = m.chat_id
        ORDER BY m.chat_id, m.id DESC
      ),
      unread_counts AS (
        SELECT
          m.chat_id,
          COUNT(*)::int AS unread_count
        FROM messages m
        JOIN user_chats uc ON uc.id = m.chat_id
        LEFT JOIN message_reads mr
          ON mr.message_id = m.id AND mr.user_id = $1
        WHERE m.user_id <> $1
          AND mr.message_id IS NULL
        GROUP BY m.chat_id
      )
      SELECT
        uc.id,
        uc.name,
        uc.is_group,
        COALESCE(ucnt.unread_count, 0) AS unread_count,
        CASE
          WHEN lm.last_message_id IS NULL THEN NULL
          ELSE json_build_object(
            'id', lm.last_message_id,
            'content', lm.last_message_content,
            'message_type', lm.last_message_type,
            'image_url', lm.last_message_image_url,
            'created_at', lm.last_message_created_at,
            'sender_email', lm.last_sender_email
          )
        END AS last_message
      FROM user_chats uc
      LEFT JOIN last_messages lm ON lm.chat_id = uc.id
      LEFT JOIN unread_counts ucnt ON ucnt.chat_id = uc.id
      ORDER BY lm.last_message_id DESC NULLS LAST, uc.id DESC
      `,
      [userId]
    );

    return res.json(result.rows);
  } catch (error) {
    console.error('Ошибка getChatsList:', error);
    return res.status(500).json({ message: 'Ошибка получения списка чатов' });
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
    const requesterId = req.user.userId;

    // Получаем информацию о чате, включая создателя
    const chatInfo = await pool.query(
      'SELECT created_by FROM chats WHERE id = $1',
      [chatId]
    );

    if (chatInfo.rows.length === 0) {
      return res.status(404).json({ message: "Чат не найден" });
    }

    const creatorId = chatInfo.rows[0].created_by;

    // Доступ к участникам только для участников чата
    const requesterMemberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, requesterId]
    );
    if (requesterMemberCheck.rows.length === 0) {
      return res.status(403).json({ message: "Вы не являетесь участником этого чата" });
    }

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
    const requesterId = req.user.userId;

    if (!Array.isArray(userIds) || userIds.length === 0) {
      return res.status(400).json({ message: "Укажите хотя бы одного участника (userIds)" });
    }

    // Проверяем, существует ли чат
    const chatCheck = await pool.query(
      'SELECT id, created_by FROM chats WHERE id = $1',
      [chatId]
    );

    if (chatCheck.rows.length === 0) {
      return res.status(404).json({ message: "Чат не найден" });
    }

    // Добавлять участников может только создатель чата
    const creatorId = chatCheck.rows[0].created_by;
    if (creatorId?.toString() !== requesterId?.toString()) {
      return res.status(403).json({ message: "Только создатель чата может добавлять участников" });
    }

    // Добавляем участников (пропускаем, если уже есть)
    const addedUsers = [];
    for (const targetUserId of userIds) {
      try {
        // Проверяем, не является ли пользователь уже участником
        const existing = await pool.query(
          'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
          [chatId, targetUserId]
        );

        if (existing.rows.length === 0) {
          await pool.query(
            `INSERT INTO chat_users (chat_id, user_id) VALUES ($1, $2)`,
            [chatId, targetUserId]
          );
          addedUsers.push(targetUserId);
        }
      } catch (e) {
        console.error(`Ошибка при добавлении пользователя ${targetUserId}:`, e);
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
    const targetUserId = req.params.userId; // Получаем из URL параметра
    const requesterId = req.user.userId;

    if (!targetUserId) {
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

    // Удалять участников может только создатель чата
    if (creatorId?.toString() !== requesterId?.toString()) {
      return res.status(403).json({ message: "Только создатель чата может удалять участников" });
    }

    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, targetUserId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(404).json({ message: "Пользователь не является участником чата" });
    }

    // Не позволяем удалить создателя чата
    if (targetUserId == creatorId || targetUserId.toString() === creatorId?.toString()) {
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
      [chatId, targetUserId]
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

// Выход из чата (пользователь сам выходит)
export const leaveChat = async (req, res) => {
  try {
    const chatId = req.params.id;
    const userId = req.user.userId; // Получаем из токена

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

    const creatorId = chatCheck.rows[0].created_by;

    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(404).json({ message: "Вы не являетесь участником этого чата" });
    }

    // Получаем количество участников
    const memberCount = await pool.query(
      'SELECT COUNT(*) as count FROM chat_users WHERE chat_id = $1',
      [chatId]
    );
    const count = parseInt(memberCount.rows[0].count);

    // Если пользователь - создатель и он последний участник, удаляем чат полностью
    const userIdStr = userId.toString();
    const creatorIdStr = creatorId?.toString();
    const isCreator = creatorIdStr && userIdStr === creatorIdStr;

    if (isCreator && count === 1) {
      // Удаляем чат полностью, так как создатель - последний участник
      await pool.query('DELETE FROM chats WHERE id = $1', [chatId]);
      res.status(200).json({ message: "Чат удален, так как вы были последним участником" });
      return;
    }

    // Если пользователь - создатель, но есть другие участники, не позволяем выйти
    // (создатель должен передать права или удалить чат)
    if (isCreator && count > 1) {
      return res.status(400).json({ 
        message: "Создатель чата не может выйти, пока есть другие участники. Удалите чат или передайте права создателя" 
      });
    }

    // Обычный участник может выйти
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

    res.status(200).json({ message: "Вы успешно вышли из чата" });

  } catch (error) {
    console.error("Ошибка leaveChat:", error);
    res.status(500).json({ message: "Ошибка выхода из чата" });
  }
};
