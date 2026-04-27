import pkg from 'pg';
const { Pool } = pkg;

import dotenv from 'dotenv';
import fs from 'fs';
dotenv.config();

// Проверка DATABASE_URL
// Значение берётся из: локально — .env (my_serve_chat_test/.env), на сервере — переменные окружения (Yandex Cloud, Render и т.д.).
// Чтобы убрать предупреждение (node:XX) про SSL, в строке подключения укажите sslmode=verify-full.
if (!process.env.DATABASE_URL) {
  console.error('❌ ОШИБКА: DATABASE_URL не установлен!');
  console.error('Установите DATABASE_URL в переменных окружения (Yandex Cloud, Render и т.д.)');
  // Не падаем сразу, чтобы можно было увидеть ошибку в логах
}

// Yandex Managed PostgreSQL использует сертификат, который pg может не доверять.
// Убираем sslmode из URL, чтобы не переопределял наш ssl (в новых pg sslmode=require → verify-full).
let connectionString = process.env.DATABASE_URL ?? '';
if (connectionString) {
  connectionString = connectionString.replace(/[?&]sslmode=[^&]*/g, '').replace(/\?&/, '?').replace(/\?$/, '');
  if (connectionString.includes('&') && !connectionString.includes('?')) connectionString = connectionString.replace('&', '?');
}
const isLocal = process.env.DATABASE_URL?.includes('localhost') ?? false;

const isProd = process.env.NODE_ENV === 'production';
const parseBool = (v) => ['1', 'true', 'yes', 'on'].includes(String(v || '').toLowerCase());

// В production по умолчанию требуем проверку сертификата.
const sslRejectUnauthorized = process.env.PGSSL_REJECT_UNAUTHORIZED != null
  ? parseBool(process.env.PGSSL_REJECT_UNAUTHORIZED)
  : isProd;

let sslCa = null;
if (process.env.PGSSL_CA_CERT && process.env.PGSSL_CA_CERT.trim()) {
  sslCa = process.env.PGSSL_CA_CERT.replace(/\\n/g, '\n');
} else if (process.env.PGSSL_CA_CERT_PATH && process.env.PGSSL_CA_CERT_PATH.trim()) {
  try {
    sslCa = fs.readFileSync(process.env.PGSSL_CA_CERT_PATH, 'utf8');
  } catch (err) {
    console.error('❌ Не удалось прочитать PGSSL_CA_CERT_PATH:', err.message);
    if (isProd) process.exit(1);
  }
}

if (isProd && !isLocal && !sslRejectUnauthorized) {
  console.error('❌ В production запрещено PGSSL_REJECT_UNAUTHORIZED=false');
  process.exit(1);
}
if (isProd && !isLocal && sslRejectUnauthorized && !sslCa) {
  console.warn(
    '⚠️ PGSSL_CA_CERT/PGSSL_CA_CERT_PATH не задан. Продолжаем со строгим TLS и системным trust store.',
  );
  console.warn(
    '⚠️ Если провайдер БД использует private CA, задайте PGSSL_CA_CERT или PGSSL_CA_CERT_PATH.',
  );
}

const pool = new Pool({
  connectionString,
  ssl: isLocal ? false : {
    rejectUnauthorized: sslRejectUnauthorized,
    ...(sslCa ? { ca: sslCa } : {}),
  },
});

// Проверка подключения к БД
pool.on('error', (err) => {
  console.error('❌ Неожиданная ошибка подключения к БД:', err);
});

// Тестовое подключение при запуске (асинхронно, не блокируем запуск)
setTimeout(() => {
  pool.query('SELECT NOW()')
    .then(() => {
      console.log('✅ Подключение к базе данных успешно');
    })
    .catch((err) => {
      console.error('❌ Ошибка подключения к базе данных:', err.message);
      console.error('Проверьте DATABASE_URL в переменных окружения');
    });
}, 1000);

export default pool;
