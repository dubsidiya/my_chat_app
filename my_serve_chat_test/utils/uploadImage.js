import multer from 'multer';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Создаем папку для загрузок, если её нет
const uploadsDir = path.join(__dirname, '../uploads/images');
try {
  if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
    console.log('Created uploads directory:', uploadsDir);
  } else {
    console.log('Uploads directory exists:', uploadsDir);
  }
} catch (error) {
  console.error('Error creating uploads directory:', error);
  throw error;
}

// Настройка хранилища для изображений
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadsDir);
  },
  filename: (req, file, cb) => {
    // Генерируем уникальное имя файла: timestamp-random-originalname
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    cb(null, `image-${uniqueSuffix}${ext}`);
  }
});

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

// Настройка multer для загрузки изображений
export const uploadImage = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024 // 10MB максимум
  },
  fileFilter: fileFilter
});

// Функция для получения URL изображения
export const getImageUrl = (filename) => {
  if (!filename) return null;
  // Возвращаем относительный путь или полный URL в зависимости от окружения
  const baseUrl = process.env.BASE_URL || 'https://my-server-chat.onrender.com';
  return `${baseUrl}/uploads/images/${filename}`;
};

// Функция для удаления изображения
export const deleteImage = (filename) => {
  if (!filename) return;
  const filePath = path.join(uploadsDir, filename);
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }
};

