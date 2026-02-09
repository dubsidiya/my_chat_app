import dotenv from 'dotenv';
import { writeFileSync, readFileSync, existsSync } from 'fs';
import { execSync } from 'child_process';

dotenv.config();

/**
 * Автоматическая настройка всего проекта
 * Запуск: node auto_setup.js
 */
//

console.log('🚀 Автоматическая настройка проекта...\n');

let envContent = '';
if (existsSync('.env')) {
  envContent = readFileSync('.env', 'utf8');
} else {
  console.log('📝 Создание файла .env...');
}

// Проверяем и добавляем недостающие переменные
let updated = false;

if (!envContent.includes('JWT_SECRET=') || envContent.includes('JWT_SECRET=your-')) {
  const jwtSecret = execSync('openssl rand -base64 32', { encoding: 'utf8' }).trim();
  if (!envContent.includes('JWT_SECRET=')) {
    envContent += `\n# JWT секретный ключ (сгенерирован автоматически)\nJWT_SECRET=${jwtSecret}\n`;
  } else {
    envContent = envContent.replace(/JWT_SECRET=.*/, `JWT_SECRET=${jwtSecret}`);
  }
  updated = true;
  console.log('✅ JWT_SECRET сгенерирован и добавлен');
}

if (!envContent.includes('ALLOWED_ORIGINS=')) {
  envContent += `\n# Разрешенные домены для CORS\nALLOWED_ORIGINS=https://my-chat-app.vercel.app,http://localhost:3000,http://localhost:8080\n`;
  updated = true;
  console.log('✅ ALLOWED_ORIGINS добавлен');
}

if (!envContent.includes('PORT=')) {
  envContent += `\n# Порт сервера\nPORT=3000\n`;
  updated = true;
  console.log('✅ PORT добавлен');
}

// DATABASE_URL - только комментарий, так как он должен быть на сервере
if (!envContent.includes('DATABASE_URL=')) {
  envContent += `\n# URL базы данных (настройте на сервере Render.com или добавьте здесь для локальной разработки)\n# DATABASE_URL=postgresql://user:password@host:port/database?sslmode=verify-full\n`;
  updated = true;
  console.log('ℹ️  DATABASE_URL - добавлен комментарий (настройте на сервере)');
}

// Яндекс Object Storage - только комментарий с инструкцией
if (!envContent.includes('YANDEX_ACCESS_KEY_ID=')) {
  envContent += `\n# Яндекс Object Storage для хранения изображений\n# Настройте согласно инструкции в YANDEX_CLOUD_SETUP.md\n# YANDEX_ACCESS_KEY_ID=ваш_access_key_id\n# YANDEX_SECRET_ACCESS_KEY=ваш_secret_access_key\n# YANDEX_BUCKET_NAME=my-chat-images\n# YANDEX_STORAGE_URL=https://my-chat-images.storage.yandexcloud.net\n`;
  updated = true;
  console.log('ℹ️  Яндекс Object Storage - добавлены комментарии (настройте для работы загрузки изображений)');
}

if (updated) {
  writeFileSync('.env', envContent.trim() + '\n');
  console.log('\n✅ Файл .env обновлен');
} else {
  console.log('\n✅ Файл .env уже настроен');
}

// Проверяем зависимости
console.log('\n📦 Проверка зависимостей...');
try {
  const packageJson = JSON.parse(readFileSync('package.json', 'utf8'));
  const requiredDeps = ['bcryptjs', 'jsonwebtoken', 'express-rate-limit', 'validator'];
  const missingDeps = requiredDeps.filter(dep => !packageJson.dependencies[dep]);
  
  if (missingDeps.length > 0) {
    console.log(`⚠️  Отсутствуют зависимости: ${missingDeps.join(', ')}`);
    console.log('📦 Установка зависимостей...');
    execSync('npm install', { stdio: 'inherit' });
    console.log('✅ Зависимости установлены');
  } else {
    console.log('✅ Все зависимости установлены');
  }
} catch (error) {
  console.log('⚠️  Не удалось проверить зависимости:', error.message);
}

console.log('\n' + '='.repeat(50));
console.log('✅ АВТОМАТИЧЕСКАЯ НАСТРОЙКА ЗАВЕРШЕНА!');
console.log('='.repeat(50));
console.log('\n📝 Следующие шаги:');
console.log('1. Если DATABASE_URL не настроен на сервере, добавьте его в .env');
console.log('2. Запустите миграцию паролей: npm run migrate-passwords');
console.log('3. Запустите сервер: npm start');
console.log('\n🚀 Готово к использованию!\n');

