import multer from 'multer';
import path from 'path';
import { uploadToYandex, deleteFromYandex } from './yandexStorage.js';

// memory storage: файл в RAM, затем в Object Storage
const storage = multer.memoryStorage();

const allowedExtensions = new Set([
  '.pdf',
  '.txt',
  '.csv',
  '.json',
  '.zip',
  '.doc',
  '.docx',
  '.xls',
  '.xlsx',
  '.ppt',
  '.pptx',
]);

// Допускаем типы документов/архивов. Если MIME приходит "кривой" (часто на web),
// разрешаем по расширению.
const allowedMimePrefixes = [
  'application/pdf',
  'text/plain',
  'text/csv',
  'application/json',
  'application/zip',
  'application/vnd',
  'application/msword',
  'application/vnd.openxmlformats-officedocument',
];

const fileFilter = (req, file, cb) => {
  const ext = path.extname(file.originalname || '').toLowerCase();
  const mimetype = (file.mimetype || '').toLowerCase();

  const okByExt = ext && allowedExtensions.has(ext);
  const okByMime = allowedMimePrefixes.some((p) => mimetype.startsWith(p));

  if (okByExt || okByMime) return cb(null, true);

  cb(new Error('Недопустимый тип файла. Разрешены: PDF, DOC/DOCX, XLS/XLSX, PPT/PPTX, TXT, CSV, JSON, ZIP'));
};

export const uploadFile = multer({
  storage,
  limits: {
    fileSize: 25 * 1024 * 1024, // 25MB
    files: 1,
  },
  fileFilter,
});

export const uploadFileToCloud = async (file, folder = 'files') => {
  if (!file || !file.buffer) throw new Error('Файл не предоставлен или отсутствует буфер');

  const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
  const ext = path.extname(file.originalname || '') || '';
  const safeExt = ext.toLowerCase();
  const fileName = `file-${uniqueSuffix}${safeExt}`;

  const url = await uploadToYandex(file.buffer, fileName, file.mimetype || 'application/octet-stream', folder);
  return {
    fileUrl: url,
    storedFileName: fileName,
    originalName: file.originalname || fileName,
    size: file.size || file.buffer.length,
    mime: file.mimetype || 'application/octet-stream',
  };
};

export const deleteFile = async (fileUrl) => {
  await deleteFromYandex(fileUrl);
};

