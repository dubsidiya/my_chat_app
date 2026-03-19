import pool from '../db.js';
import { parsePositiveInt } from '../utils/sanitize.js';
import { broadcastToChatMembers } from '../websocket/websocket.js';

const MAX_KEY_LENGTH = 256;
const MAX_BACKUP_LENGTH = 2048;

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
    const { chatId, keys } = req.body || {};
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
        `INSERT INTO chat_keys (chat_id, user_id, encrypted_key, sender_public_key, nonce, updated_at)
         VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)
         ON CONFLICT (chat_id, user_id) DO NOTHING`,
        [chatIdNum, tgtId, k.encryptedKey, k.senderPublicKey, k.nonce]
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
       LEFT JOIN chat_keys ck ON ck.chat_id = cu.chat_id AND ck.user_id = cu.user_id
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

    await broadcastToChatMembers(
      chatIdNum,
      { type: 'e2ee_request_key', chatId: String(chatIdNum), userId: String(userId) },
      { excludeUserId: userId }
    );
    return res.status(200).json({ success: true });
  } catch (error) {
    console.error('Ошибка requestChatKey:', error);
    return res.status(500).json({ message: 'Ошибка сервера' });
  }
};

export const getChatKey = async (req, res) => {
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
      'SELECT encrypted_key, sender_public_key, nonce FROM chat_keys WHERE chat_id = $1 AND user_id = $2',
      [chatIdNum, userId]
    );
    if (row.rows.length === 0) {
      return res.status(404).json({ message: 'Ключ не найден' });
    }
    const r = row.rows[0];
    return res.status(200).json({
      encryptedKey: r.encrypted_key,
      senderPublicKey: r.sender_public_key,
      nonce: r.nonce,
    });
  } catch (error) {
    console.error('Ошибка getChatKey:', error);
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
