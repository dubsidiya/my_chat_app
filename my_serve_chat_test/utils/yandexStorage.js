import { S3Client, PutObjectCommand, DeleteObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import path from 'path';

// Проверка наличия обязательных переменных окружения
const YANDEX_ACCESS_KEY_ID = process.env.YANDEX_ACCESS_KEY_ID;
const YANDEX_SECRET_ACCESS_KEY = process.env.YANDEX_SECRET_ACCESS_KEY;
const YANDEX_BUCKET_NAME = process.env.YANDEX_BUCKET_NAME;

// Проверяем, настроены ли переменные (только для предупреждения, не блокируем)
if (!YANDEX_ACCESS_KEY_ID || !YANDEX_SECRET_ACCESS_KEY || !YANDEX_BUCKET_NAME) {
  console.warn('⚠️  ВНИМАНИЕ: Переменные Яндекс Object Storage не настроены!');
  console.warn('   YANDEX_ACCESS_KEY_ID, YANDEX_SECRET_ACCESS_KEY, YANDEX_BUCKET_NAME должны быть установлены');
  console.warn('   Без них загрузка изображений не будет работать. См. YANDEX_CLOUD_SETUP.md');
}

// Конфигурация Яндекс Object Storage
const s3Client = new S3Client({
  endpoint: 'https://storage.yandexcloud.net',
  region: 'ru-central1',
  credentials: {
    accessKeyId: YANDEX_ACCESS_KEY_ID || '',
    secretAccessKey: YANDEX_SECRET_ACCESS_KEY || '',
  },
  forcePathStyle: false, // Используем виртуальный стиль (bucket.yandexcloud.net)
});

const BUCKET_NAME = YANDEX_BUCKET_NAME || 'my-chat-images';

// Базовый URL для публичного доступа
const getBaseUrl = () => {
  if (process.env.YANDEX_STORAGE_URL) {
    return process.env.YANDEX_STORAGE_URL;
  }
  return `https://${BUCKET_NAME}.storage.yandexcloud.net`;
};

/**
 * Загрузка файла в Яндекс Object Storage
 * @param {Buffer} fileBuffer - Буфер файла
 * @param {string} fileName - Имя файла
 * @param {string} contentType - MIME-тип файла
 * @param {string} folder - Папка для сохранения ('images' или 'original')
 * @returns {Promise<string>} - Публичный URL изображения
 */
export const uploadToYandex = async (fileBuffer, fileName, contentType, folder = 'images') => {
  // Проверяем наличие обязательных переменных
  if (!YANDEX_ACCESS_KEY_ID || !YANDEX_SECRET_ACCESS_KEY || !YANDEX_BUCKET_NAME) {
    throw new Error('Переменные Яндекс Object Storage не настроены. Установите YANDEX_ACCESS_KEY_ID, YANDEX_SECRET_ACCESS_KEY и YANDEX_BUCKET_NAME. См. YANDEX_CLOUD_SETUP.md');
  }

  try {
    // Путь в бакете: images/filename.jpg или original/filename.jpg
    const key = `${folder}/${fileName}`;
    
    console.log('Uploading to Yandex Cloud:', {
      bucket: BUCKET_NAME,
      key: key,
      size: fileBuffer.length,
      contentType: contentType
    });

    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      Body: fileBuffer,
      ContentType: contentType,
      ACL: 'public-read', // Публичный доступ для чтения
    });

    await s3Client.send(command);
    
    // Возвращаем публичный URL
    const imageUrl = `${getBaseUrl()}/${key}`;
    console.log('Image uploaded successfully:', imageUrl);
    
    return imageUrl;
  } catch (error) {
    console.error('Ошибка загрузки в Яндекс Облако:', error);
    
    // Более информативные сообщения об ошибках
    if (error.name === 'CredentialsProviderError' || error.message.includes('credentials')) {
      throw new Error('Ошибка аутентификации в Яндекс Облаке. Проверьте YANDEX_ACCESS_KEY_ID и YANDEX_SECRET_ACCESS_KEY');
    }
    if (error.name === 'NoSuchBucket' || error.message.includes('bucket')) {
      throw new Error(`Бакет "${BUCKET_NAME}" не найден. Проверьте YANDEX_BUCKET_NAME и убедитесь, что бакет существует в Яндекс Облаке`);
    }
    
    throw new Error(`Не удалось загрузить изображение: ${error.message}`);
  }
};

/**
 * Удаление файла из Яндекс Object Storage
 * @param {string} imageUrl - Полный URL изображения
 */
export const deleteFromYandex = async (imageUrl) => {
  try {
    if (!imageUrl) {
      console.log('No image URL provided for deletion');
      return;
    }

    // Извлекаем ключ из URL
    // URL: https://bucket.storage.yandexcloud.net/images/image-xxx.jpg
    // или: https://bucket.storage.yandexcloud.net/original/original-image-xxx.jpg
    // или: https://storage.yandexcloud.net/bucket/images/image-xxx.jpg
    let key;

    // Поддерживаем несколько папок (images/original/files)
    const folders = ['images', 'original', 'files'];
    for (const folder of folders) {
      const marker = `/${folder}/`;
      if (imageUrl.includes(marker)) {
        const parts = imageUrl.split(marker);
        if (parts.length > 1 && parts[1]) {
          key = `${folder}/${parts[1]}`;
          break;
        }

        // Альтернативный формат URL
        const urlParts = imageUrl.split('/');
        const idx = urlParts.findIndex((part) => part === folder);
        if (idx !== -1 && idx < urlParts.length - 1) {
          key = `${folder}/${urlParts.slice(idx + 1).join('/')}`;
          break;
        }
      }
    }

    if (!key) {
      console.log('URL does not contain supported folder path (images/original/files):', imageUrl);
      return;
    }

    // Простейшая валидация ключа (защита от странных URL / path traversal)
    // Разрешаем только images/original/files + безопасные символы.
    if (
      key.includes('..') ||
      key.startsWith('/') ||
      !/^(images|original|files)\/[a-zA-Z0-9._/-]+$/.test(key)
    ) {
      console.warn('Invalid storage key extracted from URL, skipping delete');
      return;
    }

    console.log('Deleting from Yandex Cloud:', { bucket: BUCKET_NAME, key });

    const command = new DeleteObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    await s3Client.send(command);
    console.log('File deleted successfully from Yandex Cloud:', key);
  } catch (error) {
    console.error('Ошибка удаления из Яндекс Облако:', error);
    // Не бросаем ошибку, чтобы не ломать удаление сообщения
  }
};

/**
 * Проверка существования файла в облаке
 * @param {string} imageUrl - Полный URL изображения
 * @returns {Promise<boolean>}
 */
export const checkFileExists = async (imageUrl) => {
  try {
    if (!imageUrl) return false;

    // Извлекаем ключ из URL (аналогично deleteFromYandex)
    let key;
    if (imageUrl.includes('/images/')) {
      const parts = imageUrl.split('/images/');
      if (parts.length > 1) {
        key = `images/${parts[1]}`;
      } else {
        return false;
      }
    } else {
      return false;
    }

    const command = new HeadObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
    });

    await s3Client.send(command);
    return true;
  } catch (error) {
    if (error.name === 'NotFound') {
      return false;
    }
    console.error('Ошибка проверки файла:', error);
    return false;
  }
};

/**
 * Получить URL изображения по имени файла
 * @param {string} fileName - Имя файла
 * @returns {string|null} - Публичный URL или null
 */
export const getImageUrl = (fileName) => {
  if (!fileName) return null;
  return `${getBaseUrl()}/images/${fileName}`;
};

