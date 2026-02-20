import pool from '../db.js';

const normalizeRole = (role) => (role || '').toString().toLowerCase();

let _chatUsersFolderColumnExists = null;
const chatUsersFolderColumnExists = async () => {
  if (_chatUsersFolderColumnExists !== null) return _chatUsersFolderColumnExists;
  try {
    const r = await pool.query(
      `
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'chat_users'
        AND column_name = 'folder'
      LIMIT 1
      `
    );
    _chatUsersFolderColumnExists = r.rows.length > 0;
    return _chatUsersFolderColumnExists;
  } catch (e) {
    // best-effort: если нет прав на information_schema — просто считаем, что колонки нет
    _chatUsersFolderColumnExists = false;
    return false;
  }
};

const getChatCreatorId = async (chatId) => {
  const r = await pool.query('SELECT created_by FROM chats WHERE id = $1', [chatId]);
  return r.rows.length ? r.rows[0].created_by?.toString() : null;
};

const getMemberRole = async (chatId, userId) => {
  const r = await pool.query(
    'SELECT role FROM chat_users WHERE chat_id = $1 AND user_id = $2',
    [chatId, userId]
  );
  if (!r.rows.length) return null;
  return normalizeRole(r.rows[0].role);
};

const isOwnerOrAdmin = async (chatId, userId) => {
  const role = await getMemberRole(chatId, userId);
  if (role === 'owner' || role === 'admin') return true;
  // fallback: если роль ещё не проставлена, считаем создателя owner
  const creatorId = await getChatCreatorId(chatId);
  return creatorId && creatorId.toString() === userId.toString();
};

const isOwner = async (chatId, userId) => {
  const role = await getMemberRole(chatId, userId);
  if (role === 'owner') return true;
  const creatorId = await getChatCreatorId(chatId);
  return creatorId && creatorId.toString() === userId.toString();
};

const generateInviteCode = () => {
  // 22 chars url-safe-ish
  const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let s = '';
  for (let i = 0; i < 22; i++) {
    s += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return s;
};

const ensureChatMember = async (chatId, userId) => {
  const r = await pool.query('SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2', [chatId, userId]);
  return r.rows.length > 0;
};

// Получение всех чатов пользователя
export const getUserChats = async (req, res) => {
  try {
    // Используем userId из токена (безопасно)
    const userId = req.user.userId;

    // Используем chat_users (как в схеме БД) вместо chat_members
    const result = await pool.query(
      `
      SELECT
        c.id,
        c.is_group,
        CASE
          WHEN c.is_group = true THEN c.name
          ELSE COALESCE(ou.display_name, ou.email, c.name)
        END AS name
      FROM chats c
      JOIN chat_users cu ON c.id = cu.chat_id AND cu.user_id = $1
      LEFT JOIN LATERAL (
        SELECT u.email, u.display_name
        FROM chat_users cu2
        JOIN users u ON u.id = cu2.user_id
        WHERE cu2.chat_id = c.id AND cu2.user_id <> $1
        ORDER BY u.id
        LIMIT 1
      ) ou ON true
      `,
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

    const hasFolder = await chatUsersFolderColumnExists();
    const folderSelect = hasFolder ? 'cu.folder AS folder' : 'NULL::text AS folder';

    const result = await pool.query(
      `
      WITH user_chats AS (
        SELECT
          c.id,
          c.is_group,
          CASE
            WHEN c.is_group = true THEN c.name
            ELSE COALESCE(ou.display_name, ou.email, c.name)
          END AS name,
          CASE WHEN c.is_group = true THEN NULL ELSE ou.id END AS other_user_id,
          CASE WHEN c.is_group = true THEN NULL ELSE ou.avatar_url END AS other_user_avatar_url,
          ${folderSelect}
        FROM chats c
        JOIN chat_users cu ON cu.chat_id = c.id AND cu.user_id = $1
        LEFT JOIN LATERAL (
          SELECT u.id, u.email, u.display_name, u.avatar_url
          FROM chat_users cu2
          JOIN users u ON u.id = cu2.user_id
          WHERE cu2.chat_id = c.id AND cu2.user_id <> $1
          ORDER BY u.id
          LIMIT 1
        ) ou ON true
      ),
      last_messages AS (
        SELECT DISTINCT ON (m.chat_id)
          m.chat_id,
          m.id AS last_message_id,
          m.content AS last_message_content,
          m.message_type AS last_message_type,
          m.image_url AS last_message_image_url,
          m.file_url AS last_message_file_url,
          m.file_name AS last_message_file_name,
          m.file_size AS last_message_file_size,
          m.file_mime AS last_message_file_mime,
          m.created_at AS last_message_created_at,
          COALESCE(u.display_name, u.email) AS last_sender_email
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
        uc.other_user_id,
        uc.other_user_avatar_url,
        uc.folder,
        COALESCE(ucnt.unread_count, 0) AS unread_count,
        CASE
          WHEN lm.last_message_id IS NULL THEN NULL
          ELSE json_build_object(
            'id', lm.last_message_id,
            'content', lm.last_message_content,
            'message_type', lm.last_message_type,
            'image_url', lm.last_message_image_url,
            'file_url', lm.last_message_file_url,
            'file_name', lm.last_message_file_name,
            'file_size', lm.last_message_file_size,
            'file_mime', lm.last_message_file_mime,
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

export const setChatFolder = async (req, res) => {
  try {
    const userId = req.user.userId;
    const chatId = req.params.id;

    const hasFolder = await chatUsersFolderColumnExists();
    if (!hasFolder) {
      return res.status(400).json({ message: 'Папки/метки чатов недоступны: примените миграцию add_chat_folders.sql' });
    }

    let folder = req.body?.folder;
    if (folder === undefined) {
      folder = req.body?.value;
    }

    if (folder === null || folder === '' || folder === false) {
      folder = null;
    } else {
      folder = String(folder).trim().toLowerCase();
      const allowed = new Set(['work', 'personal', 'archive']);
      if (!allowed.has(folder)) {
        return res.status(400).json({ message: 'Некорректная папка. Разрешено: work, personal, archive, null' });
      }
    }

    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    await pool.query(
      'UPDATE chat_users SET folder = $1 WHERE chat_id = $2 AND user_id = $3',
      [folder, chatId, userId]
    );

    return res.status(200).json({ success: true, folder });
  } catch (error) {
    console.error('Ошибка setChatFolder:', error);
    return res.status(500).json({ message: 'Ошибка обновления папки/метки чата' });
  }
};

// Создание чата
export const createChat = async (req, res) => {
  try {
    // Приложение отправляет: { name?, userIds: [userId1, ...], is_group?: boolean }
    const { name, userIds } = req.body;
    const isGroupRequested = req.body?.is_group === true || req.body?.isGroup === true || req.body?.chat_type === 'group';

    if (!Array.isArray(userIds) || userIds.length === 0) {
      return res.status(400).json({ message: "Укажите хотя бы одного участника (userIds)" });
    }

    // Создатель чата - текущий пользователь из токена
    const creatorId = req.user.userId;
    
    // Добавляем создателя в список участников, если его там нет
    if (!userIds.includes(creatorId.toString())) {
      userIds.unshift(creatorId.toString());
    }

    // Убираем дубликаты
    const uniqueUserIds = Array.from(new Set(userIds.map((x) => x.toString())));

    // ✅ 1-на-1 чат: строго 2 участника (создатель + 1 человек), и запрещаем добавления позже
    if (!isGroupRequested) {
      if (uniqueUserIds.length !== 2) {
        return res.status(400).json({ message: "Для чата 1-на-1 выберите ровно одного человека" });
      }

      const otherId = uniqueUserIds.find((x) => x !== creatorId.toString());
      // Проверим, нет ли уже такого 1-на-1 чата между этими двумя
      const existing = await pool.query(
        `
        SELECT c.id, c.name, c.is_group
        FROM chats c
        JOIN chat_users cu1 ON cu1.chat_id = c.id AND cu1.user_id = $1
        JOIN chat_users cu2 ON cu2.chat_id = c.id AND cu2.user_id = $2
        WHERE c.is_group = false
        LIMIT 1
        `,
        [creatorId.toString(), otherId]
      );
      if (existing.rows.length > 0) {
        return res.status(200).json({
          id: existing.rows[0].id?.toString(),
          name: existing.rows[0].name,
          is_group: false,
          already_exists: true,
        });
      }
    } else {
      // ✅ Групповой чат: минимум 2 участника (создатель + хотя бы 1 человек)
      if (uniqueUserIds.length < 2) {
        return res.status(400).json({ message: "Для группового чата выберите хотя бы одного участника" });
      }
      const nameTrimmed = String(name).trim();
      if (!nameTrimmed) {
        return res.status(400).json({ message: "Укажите имя группового чата" });
      }
      if (nameTrimmed.length > 100) {
        return res.status(400).json({ message: "Имя чата не более 100 символов" });
      }
    }

    const isGroup = isGroupRequested === true;
    const finalName = isGroup
      ? (name && String(name).trim().length > 0 ? String(name).trim().slice(0, 100) : 'Групповой чат')
      : 'Личный чат';

    // Создаём чат с is_group и created_by
    const chatResult = await pool.query(
      `INSERT INTO chats (name, is_group, created_by) VALUES ($1, $2, $3) RETURNING id, name, is_group, created_by`,
      [finalName, isGroup, creatorId]
    );

    const chatId = chatResult.rows[0].id;

    // Добавляем участников в chat_users (как в схеме БД)
    for (const uid of uniqueUserIds) {
      const role = uid.toString() === creatorId.toString() ? 'owner' : 'member';
      await pool.query(
        `INSERT INTO chat_users (chat_id, user_id, role) VALUES ($1, $2, $3)`,
        [chatId, uid, role]
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

    // Удалять чат может owner
    const canDelete = await isOwner(chatId, userId);
    if (!canDelete) {
      return res.status(403).json({ message: "Только владелец (owner) может удалить чат" });
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
    res.status(500).json({ 
      message: "Ошибка удаления чата",
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

    const creatorId = chatInfo.rows[0].created_by?.toString();

    // Доступ к участникам только для участников чата
    const requesterMemberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, requesterId]
    );
    if (requesterMemberCheck.rows.length === 0) {
      return res.status(403).json({ message: "Вы не являетесь участником этого чата" });
    }

    // Получаем участников чата (ник = как видят другие, аватар)
    const result = await pool.query(
      `SELECT u.id, u.email, u.display_name, u.avatar_url, cu.role
       FROM users u
       JOIN chat_users cu ON u.id = cu.user_id
       WHERE cu.chat_id = $1
       ORDER BY 
         CASE cu.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
         u.id`,
      [chatId]
    );

    const members = result.rows.map(row => ({
      id: row.id,
      email: row.email,
      display_name: row.display_name ?? null,
      displayName: row.display_name ?? row.email,
      avatar_url: row.avatar_url ?? null,
      role: row.role || (row.id?.toString() === creatorId ? 'owner' : 'member'),
      is_creator: row.id?.toString() === creatorId
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

    // ✅ Добавлять участников можно только в групповые чаты
    const groupCheck = await pool.query('SELECT is_group FROM chats WHERE id = $1', [chatId]);
    if (!groupCheck.rows[0]?.is_group) {
      return res.status(400).json({ message: "Нельзя добавлять участников в чат 1-на-1. Создайте групповой чат." });
    }

    // Добавлять участников может owner или admin
    const canAdd = await isOwnerOrAdmin(chatId, requesterId);
    if (!canAdd) {
      return res.status(403).json({ message: "Добавлять участников может только owner/admin" });
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
            `INSERT INTO chat_users (chat_id, user_id, role) VALUES ($1, $2, 'member')`,
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

    const creatorId = chatInfo.rows[0].created_by?.toString();

    const requesterRole = await getMemberRole(chatId, requesterId);
    const requesterIsOwner = requesterRole === 'owner' || (creatorId && creatorId === requesterId.toString());
    const requesterIsAdmin = requesterRole === 'admin';
    if (!requesterIsOwner && !requesterIsAdmin) {
      return res.status(403).json({ message: "Удалять участников может только owner/admin" });
    }

    // Проверяем, является ли пользователь участником чата
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, targetUserId]
    );

    if (memberCheck.rows.length === 0) {
      return res.status(404).json({ message: "Пользователь не является участником чата" });
    }

    // Не позволяем удалить владельца
    if (targetUserId.toString() === creatorId) {
      return res.status(400).json({ message: "Нельзя удалить владельца (owner) чата" });
    }

    // Если requester admin — он может удалять только member (не admin/owner)
    if (requesterIsAdmin && !requesterIsOwner) {
      const targetRole = await getMemberRole(chatId, targetUserId);
      if (targetRole === 'admin' || targetRole === 'owner' || targetUserId.toString() === creatorId) {
        return res.status(403).json({ message: "Админ не может удалять owner/admin" });
      }
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

    const creatorId = chatCheck.rows[0].created_by?.toString();

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

    // Если пользователь - owner (или создатель), и он последний участник, удаляем чат полностью
    const userIdStr = userId.toString();
    const isCreator = creatorId && userIdStr === creatorId;
    const role = await getMemberRole(chatId, userId);
    const isOwnerMember = role === 'owner' || isCreator;

    if (isCreator && count === 1) {
      // Удаляем чат полностью, так как создатель - последний участник
      await pool.query('DELETE FROM chats WHERE id = $1', [chatId]);
      res.status(200).json({ message: "Чат удален, так как вы были последним участником" });
      return;
    }

    // Если пользователь - owner и есть другие участники, не позволяем выйти (нужен transfer ownership)
    if (isOwnerMember && count > 1) {
      return res.status(400).json({ 
        message: "Owner не может выйти, пока есть другие участники. Удалите чат или передайте ownership" 
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

// ✅ Изменение роли участника (owner-only)
export const updateMemberRole = async (req, res) => {
  try {
    const chatId = req.params.id;
    const targetUserId = req.params.userId;
    const requesterId = req.user.userId;
    const role = normalizeRole(req.body?.role);

    if (!chatId || !targetUserId) {
      return res.status(400).json({ message: 'Некорректные параметры' });
    }

    // Только групповые чаты
    const groupCheck = await pool.query('SELECT is_group FROM chats WHERE id = $1', [chatId]);
    if (!groupCheck.rows[0]?.is_group) {
      return res.status(400).json({ message: 'Роли доступны только в групповых чатах' });
    }
    if (!['admin', 'member'].includes(role)) {
      return res.status(400).json({ message: "role должен быть 'admin' или 'member'" });
    }

    const owner = await isOwner(chatId, requesterId);
    if (!owner) {
      return res.status(403).json({ message: 'Только owner может менять роли' });
    }

    // target должен быть участником
    const targetRole = await getMemberRole(chatId, targetUserId);
    const creatorId = await getChatCreatorId(chatId);
    if (!targetRole && !(creatorId && creatorId === targetUserId.toString())) {
      return res.status(404).json({ message: 'Пользователь не является участником чата' });
    }
    if (creatorId && creatorId === targetUserId.toString()) {
      return res.status(400).json({ message: 'Нельзя менять роль owner через этот endpoint (используйте transfer)' });
    }

    await pool.query(
      'UPDATE chat_users SET role = $1 WHERE chat_id = $2 AND user_id = $3',
      [role, chatId, targetUserId]
    );

    return res.status(200).json({ success: true, message: 'Роль обновлена' });
  } catch (error) {
    console.error('Ошибка updateMemberRole:', error);
    return res.status(500).json({ message: 'Ошибка обновления роли' });
  }
};

// ✅ Передача ownership (owner-only)
export const transferOwnership = async (req, res) => {
  try {
    const chatId = req.params.id;
    const requesterId = req.user.userId;
    const newOwnerId = req.body?.newOwnerId?.toString();

    if (!chatId || !newOwnerId) {
      return res.status(400).json({ message: 'Укажите newOwnerId' });
    }

    // Только групповые чаты
    const groupCheck = await pool.query('SELECT is_group FROM chats WHERE id = $1', [chatId]);
    if (!groupCheck.rows[0]?.is_group) {
      return res.status(400).json({ message: 'Ownership доступен только в групповых чатах' });
    }

    const owner = await isOwner(chatId, requesterId);
    if (!owner) {
      return res.status(403).json({ message: 'Только owner может передать ownership' });
    }

    // новый owner должен быть участником
    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatId, newOwnerId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(404).json({ message: 'Новый owner должен быть участником чата' });
    }

    // текущего owner делаем admin, нового — owner
    await pool.query('UPDATE chat_users SET role = $1 WHERE chat_id = $2 AND user_id = $3', ['admin', chatId, requesterId]);
    await pool.query('UPDATE chat_users SET role = $1 WHERE chat_id = $2 AND user_id = $3', ['owner', chatId, newOwnerId]);
    await pool.query('UPDATE chats SET created_by = $1 WHERE id = $2', [newOwnerId, chatId]);

    return res.status(200).json({ success: true, message: 'Ownership передан' });
  } catch (error) {
    console.error('Ошибка transferOwnership:', error);
    return res.status(500).json({ message: 'Ошибка передачи ownership' });
  }
};

// ✅ Создать инвайт (owner/admin)
export const createInvite = async (req, res) => {
  try {
    const chatId = req.params.id;
    const requesterId = req.user.userId;
    const ttlMinutes = req.body?.ttlMinutes != null ? parseInt(req.body.ttlMinutes, 10) : null;
    const maxUses = req.body?.maxUses != null ? parseInt(req.body.maxUses, 10) : null;

    if (!chatId) return res.status(400).json({ message: 'Укажите chatId' });

    // Только групповые чаты
    const groupCheck = await pool.query('SELECT is_group FROM chats WHERE id = $1', [chatId]);
    if (!groupCheck.rows[0]?.is_group) {
      return res.status(400).json({ message: 'Инвайты доступны только для групповых чатов' });
    }

    const canCreate = await isOwnerOrAdmin(chatId, requesterId);
    if (!canCreate) {
      return res.status(403).json({ message: 'Создавать инвайт может только owner/admin' });
    }

    let expiresAt = null;
    if (Number.isFinite(ttlMinutes) && ttlMinutes > 0) {
      // ограничим TTL разумно
      const minutes = Math.min(ttlMinutes, 60 * 24 * 30); // максимум 30 дней
      expiresAt = new Date(Date.now() + minutes * 60 * 1000).toISOString();
    }

    let maxUsesVal = null;
    if (Number.isFinite(maxUses) && maxUses > 0) {
      maxUsesVal = Math.min(maxUses, 1000);
    }

    // генерируем уникальный code (несколько попыток)
    let code = null;
    for (let i = 0; i < 5; i++) {
      const candidate = generateInviteCode();
      const exists = await pool.query('SELECT 1 FROM chat_invites WHERE code = $1', [candidate]);
      if (exists.rows.length === 0) {
        code = candidate;
        break;
      }
    }
    if (!code) {
      return res.status(500).json({ message: 'Не удалось сгенерировать invite code' });
    }

    const inserted = await pool.query(
      `INSERT INTO chat_invites (chat_id, code, created_by, expires_at, max_uses)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, chat_id, code, created_at, expires_at, max_uses, use_count, revoked`,
      [chatId, code, requesterId, expiresAt, maxUsesVal]
    );

    return res.status(201).json(inserted.rows[0]);
  } catch (error) {
    console.error('Ошибка createInvite:', error);
    return res.status(500).json({ message: 'Ошибка создания инвайта' });
  }
};

// ✅ Вступить в чат по коду (member)
export const joinByInvite = async (req, res) => {
  try {
    const requesterId = req.user.userId;
    const code = (req.body?.code || '').toString().trim();

    if (!code) return res.status(400).json({ message: 'Укажите code' });
    if (code.length > 128) return res.status(400).json({ message: 'Слишком длинный code' });

    const inviteRes = await pool.query(
      `SELECT id, chat_id, expires_at, max_uses, use_count, revoked
       FROM chat_invites
       WHERE code = $1`,
      [code]
    );
    if (inviteRes.rows.length === 0) {
      return res.status(404).json({ message: 'Инвайт не найден' });
    }

    const invite = inviteRes.rows[0];
    if (invite.revoked === true) {
      return res.status(400).json({ message: 'Инвайт отозван' });
    }
    if (invite.expires_at) {
      const exp = new Date(invite.expires_at);
      if (Date.now() > exp.getTime()) {
        return res.status(400).json({ message: 'Инвайт истёк' });
      }
    }
    if (invite.max_uses != null && invite.use_count >= invite.max_uses) {
      return res.status(400).json({ message: 'Инвайт больше недоступен (лимит использований)' });
    }

    const chatId = invite.chat_id;

    // Только групповые чаты (инвайты для 1-на-1 не поддерживаем)
    const groupCheck = await pool.query('SELECT is_group FROM chats WHERE id = $1', [chatId]);
    if (!groupCheck.rows[0]?.is_group) {
      return res.status(400).json({ message: 'Инвайт ведёт в чат 1-на-1 (это запрещено)' });
    }

    // если уже участник — просто вернуть чат
    const already = await ensureChatMember(chatId, requesterId);
    if (!already) {
      await pool.query(
        `INSERT INTO chat_users (chat_id, user_id, role)
         VALUES ($1, $2, 'member')
         ON CONFLICT DO NOTHING`,
        [chatId, requesterId]
      );
      await pool.query('UPDATE chat_invites SET use_count = use_count + 1 WHERE id = $1', [invite.id]);
      // is_group уже true (см. проверку выше)
    }

    const chatRes = await pool.query('SELECT id, name, is_group FROM chats WHERE id = $1', [chatId]);
    if (chatRes.rows.length === 0) {
      return res.status(404).json({ message: 'Чат не найден' });
    }

    return res.status(200).json({
      chat: chatRes.rows[0],
      joined: !already,
    });
  } catch (error) {
    console.error('Ошибка joinByInvite:', error);
    return res.status(500).json({ message: 'Ошибка вступления по инвайту' });
  }
};

// ✅ Отозвать инвайт (owner/admin)
export const revokeInvite = async (req, res) => {
  try {
    const requesterId = req.user.userId;
    const inviteId = req.params.inviteId;

    const inv = await pool.query('SELECT id, chat_id FROM chat_invites WHERE id = $1', [inviteId]);
    if (inv.rows.length === 0) return res.status(404).json({ message: 'Инвайт не найден' });
    const chatId = inv.rows[0].chat_id;

    const can = await isOwnerOrAdmin(chatId, requesterId);
    if (!can) return res.status(403).json({ message: 'Отозвать инвайт может только owner/admin' });

    await pool.query('UPDATE chat_invites SET revoked = true WHERE id = $1', [inviteId]);
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Ошибка revokeInvite:', error);
    return res.status(500).json({ message: 'Ошибка отзыва инвайта' });
  }
};

// ✅ Переименовать чат (только групповой; owner/admin)
export const renameChat = async (req, res) => {
  try {
    const chatId = req.params.id;
    const requesterId = req.user.userId;
    const name = (req.body?.name || '').toString().trim();

    if (!chatId) return res.status(400).json({ message: 'Укажите chatId' });
    if (!name) return res.status(400).json({ message: 'Укажите name' });
    if (name.length > 100) return res.status(400).json({ message: 'Слишком длинное имя (макс 100)' });

    const chatCheck = await pool.query('SELECT is_group FROM chats WHERE id = $1', [chatId]);
    if (chatCheck.rows.length === 0) return res.status(404).json({ message: 'Чат не найден' });
    if (!chatCheck.rows[0]?.is_group) {
      return res.status(400).json({ message: 'Переименование доступно только для группового чата' });
    }

    const can = await isOwnerOrAdmin(chatId, requesterId);
    if (!can) {
      return res.status(403).json({ message: 'Переименовать чат может только owner/admin' });
    }

    const updated = await pool.query(
      'UPDATE chats SET name = $1 WHERE id = $2 RETURNING id, name, is_group',
      [name, chatId]
    );

    return res.status(200).json(updated.rows[0]);
  } catch (error) {
    console.error('Ошибка renameChat:', error);
    return res.status(500).json({ message: 'Ошибка переименования чата' });
  }
};
