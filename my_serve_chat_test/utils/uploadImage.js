import multer from 'multer';
import path from 'path';
import { uploadToYandex, deleteFromYandex, getImageUrl as getYandexImageUrl } from './yandexStorage.js';

// Используем memory storage вместо disk storage
// Файл будет храниться в памяти, затем загрузим в Яндекс Облако
const storage = multer.memoryStorage();

// Фильтр файлов - только изображения (SVG исключён: может содержать JavaScript — XSS при отображении)
const ALLOWED_IMAGE_EXT = /\.(jpeg|jpg|jpe|png|gif|webp|heic|heif|bmp|tiff|tif|avif|ico)$/i;
const ALLOWED_MIME_TYPES = [
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/x-png',
  'image/pjpeg',
  'image/heic',
  'image/heif',
  'image/bmp',
  'image/x-ms-bmp',
  'image/tiff',
  'image/avif',
  'image/x-icon',
  'image/vnd.microsoft.icon',
];

const fileFilter = (req, file, cb) => {
  const ext = path.extname(file.originalname || '').toLowerCase();
  const mimetype = (file.mimetype || '').toLowerCase();

  const okByExt = ALLOWED_IMAGE_EXT.test(ext);
  const okByMime = ALLOWED_MIME_TYPES.includes(mimetype);

  if (okByExt || okByMime) {
    return cb(null, true);
  }
  cb(new Error('Только изображения! Разрешены: JPEG, PNG, GIF, WEBP, HEIC, BMP, TIFF, AVIF, ICO'));
};

// Настройка multer для загрузки изображений (сжатое + оригинал)
export const uploadImage = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB максимум для оригинала
    files: 2 // Разрешаем до 2 файлов (сжатое + оригинал)
  },
  fileFilter: fileFilter
});

/**
 * Загрузка файла в Яндекс Облако
 * @param {Object} file - Объект файла от multer (с buffer, originalname, mimetype)
 * @param {string} folder - Папка для сохранения ('images' или 'original')
 * @returns {Promise<{imageUrl: string, fileName: string}>}
 */
export const uploadToCloud = async (file, folder = 'images') => {
  if (!file || !file.buffer) {
    throw new Error('Файл не предоставлен или отсутствует буфер');
  }

  // Генерируем уникальное имя файла
  const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
  const ext = path.extname(file.originalname || '');
  const fileName = `image-${uniqueSuffix}${ext}`;

  // Загружаем в Яндекс Облако в указанную папку
  const imageUrl = await uploadToYandex(file.buffer, fileName, file.mimetype, folder);
  
  return { imageUrl, fileName };
};

/**
 * Получить URL изображения по имени файла
 * @param {string} filename - Имя файла
 * @returns {string|null}
 */
export const getImageUrl = (filename) => {
  return getYandexImageUrl(filename);
};

/**
 * Удалить изображение из облака
 * @param {string} imageUrl - Полный URL изображения
 */
export const deleteImage = async (imageUrl) => {
  await deleteFromYandex(imageUrl);
};

