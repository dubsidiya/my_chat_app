import multer from 'multer';
import path from 'path';
import { uploadToYandex, deleteFromYandex, getImageUrl as getYandexImageUrl } from './yandexStorage.js';

// Используем memory storage вместо disk storage
// Файл будет храниться в памяти, затем загрузим в Яндекс Облако
const storage = multer.memoryStorage();

// Фильтр файлов - только изображения
const fileFilter = (req, file, cb) => {
  console.log('File filter check:', {
    originalname: file.originalname,
    mimetype: file.mimetype,
    fieldname: file.fieldname
  });

  const allowedTypes = /jpeg|jpg|png|gif|webp/;
  const allowedMimeTypes = [
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/x-png', // Альтернативный MIME для PNG
    'image/pjpeg', // Альтернативный MIME для JPEG
  ];

  // Проверяем расширение файла
  const extname = file.originalname 
    ? allowedTypes.test(path.extname(file.originalname).toLowerCase())
    : false;

  // Проверяем MIME-тип
  const mimetype = file.mimetype 
    ? allowedMimeTypes.some(type => file.mimetype.toLowerCase().includes(type.split('/')[1])) ||
      allowedMimeTypes.includes(file.mimetype.toLowerCase())
    : false;

  // Если есть хотя бы одно совпадение (расширение ИЛИ MIME-тип), разрешаем
  // Это важно для веб-платформы, где MIME-тип может быть неточным
  if (extname || mimetype) {
    console.log('File accepted:', file.originalname);
    return cb(null, true);
  } else {
    console.log('File rejected:', {
      originalname: file.originalname,
      mimetype: file.mimetype,
      extname: extname,
      mimetypeCheck: mimetype
    });
    cb(new Error('Только изображения! Разрешенные форматы: JPEG, JPG, PNG, GIF, WEBP'));
  }
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

