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

// Конфигурация S3-совместимого Object Storage.
const S3_ENDPOINT = process.env.S3_ENDPOINT || 'https://storage.yandexcloud.net';
const S3_REGION = process.env.S3_REGION || 'ru-central1';
const S3_FORCE_PATH_STYLE = ['1', 'true', 'yes'].includes(
  String(process.env.S3_FORCE_PATH_STYLE || '').toLowerCase(),
);
const s3Client = new S3Client({
  endpoint: S3_ENDPOINT,
  region: S3_REGION,
  credentials: {
    accessKeyId: YANDEX_ACCESS_KEY_ID,
    secretAccessKey: YANDEX_SECRET_ACCESS_KEY,
  },
  forcePathStyle: S3_FORCE_PATH_STYLE,
});

// Конфигурация CORS для Яндекс Object Storage
// Важно: формат должен соответствовать спецификации S3
const corsConfiguration = {
  CORSRules: [
    {
      AllowedHeaders: ['*'],
      AllowedMethods: ['GET', 'HEAD', 'OPTIONS'],
      AllowedOrigins: ['*'],
      ExposeHeaders: ['ETag', 'Content-Length', 'Content-Type', 'x-amz-request-id'],
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

  try {
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
  } catch (error) {
    // Если ошибка XML схемы, пробуем альтернативный формат
    if (error.message && error.message.includes('XML') || error.message.includes('schema')) {
      console.log('⚠️  Первая попытка не удалась, пробуем альтернативный формат...');
      
      try {
        // Альтернативный формат - более строгий
        const altCorsConfig = {
          CORSRules: [
            {
              AllowedHeaders: ['*'],
              AllowedMethods: ['GET', 'HEAD'],
              AllowedOrigins: ['*'],
              ExposeHeaders: ['ETag', 'Content-Length', 'Content-Type'],
              MaxAgeSeconds: 3000,
            },
          ],
        };
        
        const altCommand = new PutBucketCorsCommand({
          Bucket: YANDEX_BUCKET_NAME,
          CORSConfiguration: altCorsConfig,
        });
        
        await s3Client.send(altCommand);
        console.log('✅ CORS настроен с альтернативным форматом!');
      } catch (altError) {
        throw new Error(`Не удалось настроить CORS: ${error.message}. Альтернативный формат тоже не сработал: ${altError.message}`);
      }
    } else {
      throw error;
    }
  }
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

