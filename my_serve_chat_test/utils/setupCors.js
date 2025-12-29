import { S3Client, PutBucketCorsCommand } from '@aws-sdk/client-s3';
import dotenv from 'dotenv';

dotenv.config();

// Проверка переменных окружения
const YANDEX_ACCESS_KEY_ID = process.env.YANDEX_ACCESS_KEY_ID;
const YANDEX_SECRET_ACCESS_KEY = process.env.YANDEX_SECRET_ACCESS_KEY;
const YANDEX_BUCKET_NAME = process.env.YANDEX_BUCKET_NAME || 'my-chat-images';

if (!YANDEX_ACCESS_KEY_ID || !YANDEX_SECRET_ACCESS_KEY || !YANDEX_BUCKET_NAME) {
  console.error('❌ Ошибка: Переменные окружения не настроены!');
  console.error('Установите:');
  console.error('  - YANDEX_ACCESS_KEY_ID');
  console.error('  - YANDEX_SECRET_ACCESS_KEY');
  console.error('  - YANDEX_BUCKET_NAME');
  process.exit(1);
}

// Конфигурация S3 клиента для Яндекс Object Storage
const s3Client = new S3Client({
  endpoint: 'https://storage.yandexcloud.net',
  region: 'ru-central1',
  credentials: {
    accessKeyId: YANDEX_ACCESS_KEY_ID,
    secretAccessKey: YANDEX_SECRET_ACCESS_KEY,
  },
  forcePathStyle: false,
});

// Конфигурация CORS
const corsConfiguration = {
  CORSRules: [
    {
      AllowedHeaders: ['*'],
      AllowedMethods: ['GET', 'HEAD', 'OPTIONS'],
      AllowedOrigins: ['*'], // Разрешаем все источники
      ExposeHeaders: ['ETag', 'Content-Length', 'Content-Type'],
      MaxAgeSeconds: 3600,
    },
  ],
};

export async function setupCors() {
  console.log('🔧 Настройка CORS для бакета:', YANDEX_BUCKET_NAME);
  console.log('📋 Конфигурация CORS:');
  console.log('   - Разрешенные источники: * (все)');
  console.log('   - Разрешенные методы: GET, HEAD, OPTIONS');
  console.log('   - Разрешенные заголовки: * (все)');
  console.log('   - Максимальный возраст: 3600 секунд');
  console.log('');

  const command = new PutBucketCorsCommand({
    Bucket: YANDEX_BUCKET_NAME,
    CORSConfiguration: corsConfiguration,
  });

  await s3Client.send(command);

  console.log('✅ CORS успешно настроен!');
  console.log('');
  console.log('📝 Теперь изображения должны отображаться в приложении.');
  console.log('   Если проблема сохраняется, проверьте:');
  console.log('   1. Что бакет имеет тип доступа "Публичный"');
  console.log('   2. Что переменные окружения правильные');
  console.log('   3. Обновите страницу в браузере (Ctrl+F5)');
}

// Если скрипт запущен напрямую (не импортирован)
// Проверяем через process.argv
const isMainModule = process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/'));
if (isMainModule) {
  setupCors()
    .then(() => {
      console.log('✅ Готово!');
      process.exit(0);
    })
    .catch((error) => {
      console.error('❌ Ошибка настройки CORS:', error);
      
      if (error.name === 'NoSuchBucket') {
        console.error(`   Бакет "${YANDEX_BUCKET_NAME}" не найден.`);
        console.error('   Проверьте YANDEX_BUCKET_NAME в переменных окружения.');
      } else if (error.name === 'AccessDenied' || error.message.includes('Access Denied')) {
        console.error('   Доступ запрещен. Проверьте:');
        console.error('   - Правильность YANDEX_ACCESS_KEY_ID и YANDEX_SECRET_ACCESS_KEY');
        console.error('   - Что сервисный аккаунт имеет роль storage.editor');
      } else {
        console.error('   Детали ошибки:', error.message);
      }
      
      process.exit(1);
    });
}

