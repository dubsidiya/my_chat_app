/**
 * One-time миграция: расшифровать историю сообщений, зашифрованных старой
 * клиентской схемой (AES-256-GCM ключом чата `chats.shared_chat_key`),
 * и записать открытый текст обратно в `messages.content`.
 *
 * Зачем: шифрование чата было убрано (ключ всё равно хранился на сервере, это не
 * настоящий E2EE). Новые сообщения идут открытым текстом; старые лежат в БД как
 * JSON `{"v":"1","ct":"<base64 ct+mac>","n":"<base64 nonce>"}` и в приложении
 * показываются как «Сообщение недоступно». Этот скрипт возвращает их текст.
 *
 * Безопасность:
 *  - AES-GCM аутентифицирован: при неверном ключе расшифровка бросает исключение,
 *    такое сообщение ПРОПУСКАЕТСЯ и остаётся нетронутым (например, старые legacy-чаты
 *    на X25519, чей ключ серверу неизвестен).
 *  - По умолчанию это DRY-RUN (ничего не пишет). Для записи добавьте `--apply`.
 *
 * Запуск:
 *   node scripts/decrypt-legacy-messages.js                 # отчёт без изменений (dry-run)
 *   node scripts/decrypt-legacy-messages.js --chat=123      # только один чат (dry-run)
 *   node scripts/decrypt-legacy-messages.js --apply         # записать расшифровку в БД
 *   node scripts/decrypt-legacy-messages.js --chat=123 --apply
 *
 * Требует DATABASE_URL (как и сервер) — берётся из my_serve_chat_test/.env или окружения.
 */
import crypto from 'crypto';
import pool from '../db.js';

const APPLY = process.argv.includes('--apply');
const chatArg = process.argv.find((a) => a.startsWith('--chat='));
const ONLY_CHAT_ID = chatArg ? chatArg.slice('--chat='.length) : null;

const BATCH_SIZE = 500;
const GCM_TAG_LEN = 16;
const PREVIEW_SAMPLES = 5;

/** Похоже ли содержимое на старый зашифрованный формат сообщения. */
function looksEncrypted(content) {
  if (typeof content !== 'string' || !content.startsWith('{')) return false;
  try {
    const d = JSON.parse(content);
    return Boolean(d && d.v === '1' && typeof d.ct === 'string' && typeof d.n === 'string');
  } catch (_) {
    return false;
  }
}

/**
 * Пытается расшифровать содержимое ключом чата (base64).
 * Возвращает открытый текст или null, если ключ не подходит / формат не тот.
 */
function tryDecrypt(content, keyB64) {
  let data;
  try {
    data = JSON.parse(content);
  } catch (_) {
    return null;
  }
  if (!data || data.v !== '1' || typeof data.ct !== 'string' || typeof data.n !== 'string') {
    return null;
  }

  let key;
  let ct;
  let nonce;
  try {
    key = Buffer.from(keyB64, 'base64');
    ct = Buffer.from(data.ct, 'base64');
    nonce = Buffer.from(data.n, 'base64');
  } catch (_) {
    return null;
  }
  if (key.length !== 32) return null; // ожидаем AES-256
  if (ct.length <= GCM_TAG_LEN) return null;

  const cipherText = ct.subarray(0, ct.length - GCM_TAG_LEN);
  const authTag = ct.subarray(ct.length - GCM_TAG_LEN);

  try {
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, nonce);
    decipher.setAuthTag(authTag);
    const out = Buffer.concat([decipher.update(cipherText), decipher.final()]);
    return out.toString('utf8');
  } catch (_) {
    // Неверный ключ / повреждено / чужая версия ключа — не трогаем сообщение.
    return null;
  }
}

async function main() {
  console.log(`▶️  decrypt-legacy-messages — режим: ${APPLY ? 'APPLY (запись в БД)' : 'DRY-RUN (без изменений)'}`);
  if (ONLY_CHAT_ID) console.log(`   Ограничение: только чат ${ONLY_CHAT_ID}`);

  // 1) Загружаем ключи чатов в память.
  const keysRes = await pool.query(
    `SELECT id, shared_chat_key
       FROM chats
      WHERE shared_chat_key IS NOT NULL
        AND shared_chat_key <> ''
        ${ONLY_CHAT_ID ? 'AND id = $1' : ''}`,
    ONLY_CHAT_ID ? [ONLY_CHAT_ID] : []
  );
  const keyByChat = new Map();
  for (const row of keysRes.rows) keyByChat.set(String(row.id), row.shared_chat_key);
  console.log(`🔑 Чатов с общим ключом: ${keyByChat.size}`);

  if (keyByChat.size === 0) {
    console.log('Нет чатов с shared_chat_key — расшифровывать нечего (возможно, всё на legacy X25519).');
    await pool.end();
    return;
  }

  const stats = {
    scanned: 0,
    encrypted: 0,
    decrypted: 0,
    skippedNoKey: 0,
    failed: 0,
    updated: 0,
  };
  const samples = [];
  const skippedByChat = new Map(); // chat_id -> count (сообщения без ключа на сервере)

  // 2) Идём по сообщениям батчами (постранично по возрастанию id).
  let lastId = 0;
  for (;;) {
    const res = await pool.query(
      `SELECT id, chat_id, content
         FROM messages
        WHERE id > $1
          AND content LIKE '{%'
          ${ONLY_CHAT_ID ? 'AND chat_id = $3' : ''}
        ORDER BY id ASC
        LIMIT $2`,
      ONLY_CHAT_ID ? [lastId, BATCH_SIZE, ONLY_CHAT_ID] : [lastId, BATCH_SIZE]
    );
    if (res.rows.length === 0) break;

    for (const row of res.rows) {
      lastId = row.id;
      stats.scanned++;
      if (!looksEncrypted(row.content)) continue;
      stats.encrypted++;

      const key = keyByChat.get(String(row.chat_id));
      if (!key) {
        stats.skippedNoKey++;
        const cid = String(row.chat_id);
        skippedByChat.set(cid, (skippedByChat.get(cid) || 0) + 1);
        continue;
      }

      const plain = tryDecrypt(row.content, key);
      if (plain == null) {
        stats.failed++;
        continue;
      }
      stats.decrypted++;

      if (samples.length < PREVIEW_SAMPLES) {
        const preview = plain.length > 40 ? `${plain.slice(0, 40)}…` : plain;
        samples.push(`   #${row.id} (chat ${row.chat_id}): "${preview}"`);
      }

      if (APPLY) {
        await pool.query('UPDATE messages SET content = $1 WHERE id = $2', [plain, row.id]);
        stats.updated++;
      }
    }
  }

  console.log('\n— Итог —');
  console.log(`Просмотрено сообщений (начинающихся с "{"): ${stats.scanned}`);
  console.log(`Из них зашифрованных:                       ${stats.encrypted}`);
  console.log(`Успешно расшифровано:                       ${stats.decrypted}`);
  console.log(`Пропущено (нет ключа чата на сервере):       ${stats.skippedNoKey}`);
  console.log(`Не подошёл ключ / повреждено (пропущено):    ${stats.failed}`);
  console.log(`Записано в БД:                              ${stats.updated}${APPLY ? '' : ' (dry-run)'}`);

  if (samples.length) {
    console.log('\nПримеры расшифровки:');
    for (const s of samples) console.log(s);
  }

  // Диагностика непокрытых чатов: есть ли у них legacy-ключи (chat_keys) и сколько участников.
  if (skippedByChat.size > 0) {
    const skippedChatIds = [...skippedByChat.keys()];
    let legacyByChat = new Map();
    try {
      const legacyRes = await pool.query(
        `SELECT chat_id, COUNT(*)::int AS n FROM chat_keys WHERE chat_id = ANY($1) GROUP BY chat_id`,
        [skippedChatIds]
      );
      legacyByChat = new Map(legacyRes.rows.map((r) => [String(r.chat_id), r.n]));
    } catch (e) {
      console.log(`\n(не удалось проверить chat_keys: ${e.message})`);
    }
    console.log('\nЧаты без ключа на сервере (сообщения не расшифрованы):');
    for (const cid of skippedChatIds) {
      const legacy = legacyByChat.get(cid) || 0;
      const tag = legacy > 0
        ? `legacy chat_keys: ${legacy} (нужен приватный ключ устройства/пароль — сервер расшифровать не может)`
        : 'ключей нет нигде (восстановить невозможно)';
      console.log(`   chat ${cid}: ${skippedByChat.get(cid)} сообщ. — ${tag}`);
    }
  }

  if (!APPLY && stats.decrypted > 0) {
    console.log('\nℹ️  Это был DRY-RUN. Чтобы записать изменения, повторите с флагом --apply.');
  }

  await pool.end();
  process.exit(0); // чистый выход: гасим фоновый тест-коннект из db.js
}

main().catch(async (err) => {
  console.error('❌ Ошибка миграции:', err);
  try {
    await pool.end();
  } catch (_) {}
  process.exit(1);
});
