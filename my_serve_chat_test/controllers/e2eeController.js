import crypto from 'crypto';
import pool from '../db.js';
import { parsePositiveInt } from '../utils/sanitize.js';
import { broadcastToChatMembers } from '../websocket/websocket.js';

const MAX_KEY_LENGTH = 256;
const MAX_BACKUP_LENGTH = 2048;
// AES-256 ключ в base64: 44 символа без паддинга/с паддингом. Берём с запасом.
const MAX_SHARED_KEY_LENGTH = 128;
const parseKeyVersion = (x) => {
  const n = parseInt(x, 10);
  return Number.isFinite(n) && n > 0 ? n : null;
};

const generateSharedChatKeyB64 = () => crypto.randomBytes(32).toString('base64');

export const uploadPublicKey = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { publicKey } = req.body || {};
    if (!publicKey || typeof publicKey !== 'string' || publicKey.length > MAX_KEY_LENGTH) {
      return res.status(400).json({ message: 'Некорректный publicKey' });
    }
    await pool.query(
      'UPDATE users SET public_key = $1 WHERE id = $2',
      [publicKey.trim(), userId]
    );
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Ошибка uploadPublicKey:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const getPublicKey = async (req, res) => {
  try {
    const targetId = parsePositiveInt(req.params?.userId);
    if (!targetId) return res.status(400).json({ message: 'Некорректный userId' });

    const row = await pool.query(
      'SELECT public_key FROM users WHERE id = $1',
      [targetId]
    );
    if (row.rows.length === 0) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    return res.status(200).json({ publicKey: row.rows[0].public_key ?? null });
  } catch (error) {
    console.error('Ошибка getPublicKey:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const getPublicKeys = async (req, res) => {
  try {
    const { userIds } = req.body || {};
    if (!Array.isArray(userIds) || userIds.length === 0 || userIds.length > 100) {
      return res.status(400).json({ message: 'userIds — массив от 1 до 100 элементов' });
    }
    const ids = userIds.map((x) => parseInt(x, 10)).filter(Number.isFinite);
    if (ids.length === 0) return res.status(400).json({ message: 'Некорректные userIds' });

    const rows = await pool.query(
      'SELECT id, public_key FROM users WHERE id = ANY($1)',
      [ids]
    );
    const map = {};
    rows.rows.forEach((r) => { map[r.id] = r.public_key ?? null; });
    return res.status(200).json({ keys: map });
  } catch (error) {
    console.error('Ошибка getPublicKeys:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const storeChatKeys = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { chatId, keys, keyVersion } = req.body || {};
    const chatIdNum = parsePositiveInt(chatId);
    if (!chatIdNum) return res.status(400).json({ message: 'Некорректный chatId' });

    if (!Array.isArray(keys) || keys.length === 0 || keys.length > 100) {
      return res.status(400).json({ message: 'keys — массив от 1 до 100 элементов' });
    }

    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatIdNum, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    const chatMeta = await pool.query(
      'SELECT current_key_version FROM chats WHERE id = $1',
      [chatIdNum]
    );
    if (chatMeta.rows.length === 0) {
      return res.status(404).json({ message: 'Чат не найден' });
    }
    const effectiveVersion = Number.isFinite(parseInt(keyVersion, 10))
      ? parseInt(keyVersion, 10)
      : parseInt(chatMeta.rows[0].current_key_version, 10) || 1;

    const chatMembers = await pool.query(
      'SELECT user_id FROM chat_users WHERE chat_id = $1',
      [chatIdNum]
    );
    const memberIdSet = new Set(chatMembers.rows.map((r) => r.user_id));

    for (const k of keys) {
      if (!k.userId || !k.encryptedKey || !k.senderPublicKey || !k.nonce) continue;
      const tgtId = parsePositiveInt(k.userId);
      if (!tgtId || !memberIdSet.has(tgtId)) continue;
      if (String(k.encryptedKey).length > 1024 || String(k.senderPublicKey).length > MAX_KEY_LENGTH || String(k.nonce).length > 128) continue;

      await pool.query(
        `INSERT INTO chat_keys (chat_id, user_id, key_version, encrypted_key, sender_public_key, nonce, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)
         ON CONFLICT (chat_id, user_id, key_version) DO UPDATE
         SET encrypted_key = EXCLUDED.encrypted_key,
             sender_public_key = EXCLUDED.sender_public_key,
             nonce = EXCLUDED.nonce,
             updated_at = CURRENT_TIMESTAMP`,
        [chatIdNum, tgtId, effectiveVersion, k.encryptedKey, k.senderPublicKey, k.nonce]
      );
      await pool.query(
        `INSERT INTO chat_key_requests (chat_id, requester_user_id, key_version, status, updated_at)
         VALUES ($1, $2, $3, 'fulfilled', CURRENT_TIMESTAMP)
         ON CONFLICT (chat_id, requester_user_id, key_version) DO UPDATE
         SET status = 'fulfilled', updated_at = CURRENT_TIMESTAMP`,
        [chatIdNum, tgtId, effectiveVersion]
      );
    }
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Ошибка storeChatKeys:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

/**
 * Участники чата, у которых ещё нет записи в chat_keys (например, вошли по инвайту).
 * Нужен чтобы клиент мог отправить им ключ чата (shareChatKeyWithNewMembers).
 */
export const getMembersWithoutChatKey = async (req, res) => {
  try {
    const userId = req.user.userId;
    const chatIdNum = parsePositiveInt(req.params?.chatId);
    if (!chatIdNum) return res.status(400).json({ message: 'Некорректный chatId' });

    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatIdNum, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    const result = await pool.query(
      `SELECT cu.user_id FROM chat_users cu
       JOIN chats c ON c.id = cu.chat_id
       LEFT JOIN chat_keys ck
         ON ck.chat_id = cu.chat_id
        AND ck.user_id = cu.user_id
        AND ck.key_version = c.current_key_version
       WHERE cu.chat_id = $1 AND ck.user_id IS NULL`,
      [chatIdNum]
    );
    const userIds = result.rows.map((r) => String(r.user_id));
    return res.status(200).json({ userIds });
  } catch (error) {
    console.error('Ошибка getMembersWithoutChatKey:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

/** E2EE: новый участник запрашивает ключ чата; сервер рассылает другим участникам WS, те отдают ключ через shareChatKeyWithNewMembers */
export const requestChatKey = async (req, res) => {
  try {
    const requestedVersion = parseKeyVersion(req.body?.keyVersion);
    const userId = req.user.userId;
    const chatIdNum = parsePositiveInt(req.params?.chatId);
    if (!chatIdNum) return res.status(400).json({ message: 'Некорректный chatId' });

    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatIdNum, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    const chatMeta = await pool.query(
      'SELECT current_key_version FROM chats WHERE id = $1',
      [chatIdNum]
    );
    if (chatMeta.rows.length === 0) {
      return res.status(404).json({ message: 'Чат не найден' });
    }
    const effectiveVersion = requestedVersion ?? (parseInt(chatMeta.rows[0].current_key_version, 10) || 1);

    // Если у requester уже есть ключ нужной версии, не создаём/не шлём лишние запросы.
    const requesterHasKey = await pool.query(
      'SELECT 1 FROM chat_keys WHERE chat_id = $1 AND user_id = $2 AND key_version = $3',
      [chatIdNum, userId, effectiveVersion]
    );
    if (requesterHasKey.rows.length > 0) {
      await pool.query(
        `INSERT INTO chat_key_requests (chat_id, requester_user_id, key_version, status, updated_at)
         VALUES ($1, $2, $3, 'fulfilled', CURRENT_TIMESTAMP)
         ON CONFLICT (chat_id, requester_user_id, key_version) DO UPDATE
         SET status = 'fulfilled', updated_at = CURRENT_TIMESTAMP`,
        [chatIdNum, userId, effectiveVersion]
      );
      return res.status(200).json({ success: true, alreadyHasKey: true, keyVersion: effectiveVersion });
    }

    const existingRequest = await pool.query(
      `SELECT status
       FROM chat_key_requests
       WHERE chat_id = $1
         AND requester_user_id = $2
         AND key_version = $3
       LIMIT 1`,
      [chatIdNum, userId, effectiveVersion]
    );
    const wasAlreadyPending =
      existingRequest.rows.length > 0 &&
      String(existingRequest.rows[0].status || '').toLowerCase() === 'pending';

    await pool.query(
      `INSERT INTO chat_key_requests (chat_id, requester_user_id, key_version, status, updated_at)
       VALUES ($1, $2, $3, 'pending', CURRENT_TIMESTAMP)
       ON CONFLICT (chat_id, requester_user_id, key_version) DO UPDATE
       SET status = 'pending', updated_at = CURRENT_TIMESTAMP`,
      [chatIdNum, userId, effectiveVersion]
    );

    // Дедуп: если активный pending уже был, повторно не рассылаем WS-запрос.
    if (!wasAlreadyPending) {
      await broadcastToChatMembers(
        chatIdNum,
        { type: 'e2ee_request_key', chatId: String(chatIdNum), userId: String(userId), keyVersion: effectiveVersion },
        { excludeUserId: userId }
      );
    }
    return res.status(200).json({ success: true, keyVersion: effectiveVersion });
  } catch (error) {
    console.error('Ошибка requestChatKey:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const getPendingKeyRequests = async (req, res) => {
  try {
    const userId = req.user.userId;
    const chatIdNum = parsePositiveInt(req.params?.chatId);
    if (!chatIdNum) return res.status(400).json({ message: 'Некорректный chatId' });

    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatIdNum, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    const rows = await pool.query(
      `SELECT requester_user_id, key_version, updated_at
       FROM chat_key_requests
       WHERE chat_id = $1
         AND status = 'pending'
         AND requester_user_id <> $2
       ORDER BY updated_at DESC
       LIMIT 100`,
      [chatIdNum, userId]
    );
    return res.status(200).json({
      requests: rows.rows.map((r) => ({
        requesterUserId: String(r.requester_user_id),
        keyVersion: parseInt(r.key_version, 10) || 1,
        updatedAt: r.updated_at,
      })),
    });
  } catch (error) {
    console.error('Ошибка getPendingKeyRequests:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const getChatKey = async (req, res) => {
  try {
    const userId = req.user.userId;
    const chatIdNum = parsePositiveInt(req.params?.chatId);
    if (!chatIdNum) return res.status(400).json({ message: 'Некорректный chatId' });
    const requestedVersion = req.query?.keyVersion ? parseInt(req.query.keyVersion, 10) : null;

    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatIdNum, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    const chatMeta = await pool.query(
      'SELECT current_key_version FROM chats WHERE id = $1',
      [chatIdNum]
    );
    if (chatMeta.rows.length === 0) {
      return res.status(404).json({ message: 'Чат не найден' });
    }
    const effectiveVersion = Number.isFinite(requestedVersion)
      ? requestedVersion
      : parseInt(chatMeta.rows[0].current_key_version, 10) || 1;

    const row = await pool.query(
      `SELECT encrypted_key, sender_public_key, nonce, key_version
       FROM chat_keys
       WHERE chat_id = $1 AND user_id = $2 AND key_version = $3`,
      [chatIdNum, userId, effectiveVersion]
    );
    if (row.rows.length === 0) {
      return res.status(404).json({ message: 'Ключ не найден' });
    }
    const r = row.rows[0];
    return res.status(200).json({
      encryptedKey: r.encrypted_key,
      senderPublicKey: r.sender_public_key,
      nonce: r.nonce,
      keyVersion: r.key_version,
    });
  } catch (error) {
    console.error('Ошибка getChatKey:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

/**
 * Упрощённый E2EE: сервер хранит один общий AES-ключ на чат и выдаёт его любому участнику.
 * Используется в новых чатах. Для совместимости со старыми чатами этот эндпоинт может
 * вернуть 404, тогда клиент откатится на пер-юзерный путь.
 */
export const getSharedChatKey = async (req, res) => {
  try {
    const userId = req.user.userId;
    const chatIdNum = parsePositiveInt(req.params?.chatId);
    if (!chatIdNum) return res.status(400).json({ message: 'Некорректный chatId' });

    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatIdNum, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    const row = await pool.query(
      `SELECT shared_chat_key, COALESCE(current_key_version, 1) AS current_key_version
       FROM chats
       WHERE id = $1`,
      [chatIdNum]
    );
    if (row.rows.length === 0) {
      return res.status(404).json({ message: 'Чат не найден' });
    }
    const sharedKey = row.rows[0].shared_chat_key;
    if (!sharedKey) {
      return res.status(404).json({ message: 'Общий ключ чата отсутствует' });
    }
    return res.status(200).json({
      chatKey: sharedKey,
      keyVersion: parseInt(row.rows[0].current_key_version, 10) || 1,
    });
  } catch (error) {
    console.error('Ошибка getSharedChatKey:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

/**
 * Идемпотентно сохраняет общий ключ чата: либо клиент явно передаёт его, либо сервер
 * генерирует новый. Перезаписать уже существующий нельзя — это защищает от гонки и от
 * потери истории. Используется создателем нового чата и для бэкфилла из старого пути.
 */
export const setSharedChatKey = async (req, res) => {
  try {
    const userId = req.user.userId;
    const chatIdNum = parsePositiveInt(req.params?.chatId);
    if (!chatIdNum) return res.status(400).json({ message: 'Некорректный chatId' });

    const memberCheck = await pool.query(
      'SELECT 1 FROM chat_users WHERE chat_id = $1 AND user_id = $2',
      [chatIdNum, userId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(403).json({ message: 'Вы не являетесь участником этого чата' });
    }

    const provided = (req.body?.chatKey ?? '').toString().trim();
    let candidate = provided;
    if (candidate) {
      if (candidate.length > MAX_SHARED_KEY_LENGTH) {
        return res.status(400).json({ message: 'Слишком длинный chatKey' });
      }
      if (!/^[A-Za-z0-9+/=_-]+$/.test(candidate)) {
        return res.status(400).json({ message: 'Некорректный chatKey' });
      }
    } else {
      candidate = generateSharedChatKeyB64();
    }

    const update = await pool.query(
      `UPDATE chats
       SET shared_chat_key = $1
       WHERE id = $2 AND (shared_chat_key IS NULL OR shared_chat_key = '')
       RETURNING shared_chat_key, COALESCE(current_key_version, 1) AS current_key_version`,
      [candidate, chatIdNum]
    );

    if (update.rows.length > 0) {
      return res.status(200).json({
        chatKey: update.rows[0].shared_chat_key,
        keyVersion: parseInt(update.rows[0].current_key_version, 10) || 1,
        created: true,
      });
    }

    const existing = await pool.query(
      `SELECT shared_chat_key, COALESCE(current_key_version, 1) AS current_key_version
       FROM chats
       WHERE id = $1`,
      [chatIdNum]
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ message: 'Чат не найден' });
    }
    return res.status(200).json({
      chatKey: existing.rows[0].shared_chat_key,
      keyVersion: parseInt(existing.rows[0].current_key_version, 10) || 1,
      created: false,
    });
  } catch (error) {
    console.error('Ошибка setSharedChatKey:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const storeKeyBackup = async (req, res) => {
  try {
    const userId = req.user.userId;
    const { encryptedPrivateKey, salt, nonce, publicKey } = req.body || {};
    if (!encryptedPrivateKey || !salt || !nonce || !publicKey) {
      return res.status(400).json({ message: 'encryptedPrivateKey, salt, nonce, publicKey обязательны' });
    }
    if (String(encryptedPrivateKey).length > MAX_BACKUP_LENGTH ||
        String(salt).length > MAX_KEY_LENGTH ||
        String(nonce).length > MAX_KEY_LENGTH ||
        String(publicKey).length > MAX_KEY_LENGTH) {
      return res.status(400).json({ message: 'Слишком длинные параметры' });
    }

    await pool.query(
      `UPDATE users
       SET encrypted_key_backup = $1, key_backup_salt = $2, key_backup_nonce = $3, public_key = $4
       WHERE id = $5`,
      [encryptedPrivateKey, salt, nonce, publicKey, userId]
    );
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Ошибка storeKeyBackup:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const getKeyBackup = async (req, res) => {
  try {
    const userId = req.user.userId;
    const row = await pool.query(
      'SELECT encrypted_key_backup, key_backup_salt, key_backup_nonce, public_key FROM users WHERE id = $1',
      [userId]
    );
    if (row.rows.length === 0) {
      return res.status(404).json({ message: 'Пользователь не найден' });
    }
    const r = row.rows[0];
    if (!r.encrypted_key_backup) {
      return res.status(404).json({ message: 'Бэкап ключей не найден' });
    }
    return res.status(200).json({
      encryptedPrivateKey: r.encrypted_key_backup,
      salt: r.key_backup_salt,
      nonce: r.key_backup_nonce,
      publicKey: r.public_key,
    });
  } catch (error) {
    console.error('Ошибка getKeyBackup:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};
