import dotenv from 'dotenv';
dotenv.config();

/**
 * Скрипт проверки настройки безопасности
 * Запустите: node check_setup.js
 */

console.log('🔍 Проверка настройки безопасности...\n');

const errors = [];
const warnings = [];

// Проверка JWT_SECRET
const jwtSecret = process.env.JWT_SECRET;
if (!jwtSecret) {
  errors.push('❌ JWT_SECRET не установлен в .env');
} else if (jwtSecret === 'your-secret-key-change-in-production' || jwtSecret.length < 32) {
  warnings.push('⚠️  JWT_SECRET должен быть длинной случайной строкой (минимум 32 символа)');
} else {
  console.log('✅ JWT_SECRET установлен');
}

// Проверка ALLOWED_ORIGINS
const allowedOrigins = process.env.ALLOWED_ORIGINS;
if (!allowedOrigins) {
  warnings.push('⚠️  ALLOWED_ORIGINS не установлен - будут использоваться значения по умолчанию');
} else {
  console.log('✅ ALLOWED_ORIGINS установлен:', allowedOrigins);
}

// Проверка DATABASE_URL
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  // DATABASE_URL может быть настроен на сервере (Yandex Cloud, Render и т.д.), поэтому это предупреждение, а не ошибка
  warnings.push('⚠️  DATABASE_URL не установлен в .env (должен быть настроен на сервере: Yandex Cloud, Render и т.д.)');
} else {
  console.log('✅ DATABASE_URL установлен');
}

// Проверка переменных Яндекс Object Storage
const yandexAccessKey = process.env.YANDEX_ACCESS_KEY_ID;
const yandexSecretKey = process.env.YANDEX_SECRET_ACCESS_KEY;
const yandexBucket = process.env.YANDEX_BUCKET_NAME;

if (!yandexAccessKey || !yandexSecretKey || !yandexBucket) {
  warnings.push('⚠️  Переменные Яндекс Object Storage не настроены (YANDEX_ACCESS_KEY_ID, YANDEX_SECRET_ACCESS_KEY, YANDEX_BUCKET_NAME)');
  warnings.push('   Без них загрузка изображений не будет работать. См. YANDEX_CLOUD_SETUP.md');
} else {
  console.log('✅ Переменные Яндекс Object Storage настроены');
  console.log(`   Бакет: ${yandexBucket}`);
}

// Проверка зависимостей
try {
  await import('bcryptjs');
  console.log('✅ bcryptjs установлен');
} catch (e) {
  errors.push('❌ bcryptjs не установлен - запустите: npm install');
}

try {
  await import('jsonwebtoken');
  console.log('✅ jsonwebtoken установлен');
} catch (e) {
  errors.push('❌ jsonwebtoken не установлен - запустите: npm install');
}

try {
  await import('express-rate-limit');
  console.log('✅ express-rate-limit установлен');
} catch (e) {
  errors.push('❌ express-rate-limit не установлен - запустите: npm install');
}

try {
  await import('validator');
  console.log('✅ validator установлен');
} catch (e) {
  errors.push('❌ validator не установлен - запустите: npm install');
}

// Итоги
console.log('\n' + '='.repeat(50));

if (errors.length > 0) {
  console.log('❌ ОШИБКИ:');
  errors.forEach(err => console.log('  ' + err));
  console.log('\n⚠️  Сервер не запустится с этими ошибками!');
}

if (warnings.length > 0) {
  console.log('\n⚠️  ПРЕДУПРЕЖДЕНИЯ:');
  warnings.forEach(warn => console.log('  ' + warn));
}

if (errors.length === 0 && warnings.length === 0) {
  console.log('✅ ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ!');
  console.log('\n🚀 Можно запускать сервер: npm start');
} else if (errors.length === 0) {
  console.log('\n✅ Критических ошибок нет, но есть предупреждения');
  console.log('🚀 Сервер можно запустить, но рекомендуется исправить предупреждения');
}

console.log('='.repeat(50));

process.exit(errors.length > 0 ? 1 : 0);

