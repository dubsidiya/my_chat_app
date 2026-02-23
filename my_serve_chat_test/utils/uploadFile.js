import multer from 'multer';
import path from 'path';
import { uploadToYandex, deleteFromYandex } from './yandexStorage.js';

// Санитизация имени файла: только basename, без path traversal, макс. длина
const MAX_ORIGINAL_NAME_LENGTH = 255;
const sanitizeOriginalName = (name) => {
  if (!name || typeof name !== 'string') return 'file';
  const base = path.basename(name.trim()).replace(/\0/g, '');
  if (base.length > MAX_ORIGINAL_NAME_LENGTH) return base.slice(0, MAX_ORIGINAL_NAME_LENGTH);
  return base || 'file';
};

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
  // код
  '.py',
  '.js',
  '.ts',
  '.html',
  '.css',
  // audio (voice messages)
  '.m4a',
  '.aac',
  '.mp3',
  '.ogg',
  '.opus',
  '.wav',
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
  // код (Python, JS, HTML, CSS и т.д.)
  'text/x-python',
  'application/x-python',
  'text/javascript',
  'text/html',
  'text/css',
  // audio (voice messages)
  'audio/',
];

const fileFilter = (req, file, cb) => {
  const ext = path.extname(file.originalname || '').toLowerCase();
  const mimetype = (file.mimetype || '').toLowerCase();

  const okByExt = ext && allowedExtensions.has(ext);
  const okByMime = allowedMimePrefixes.some((p) => mimetype.startsWith(p));

  if (okByExt || okByMime) return cb(null, true);

  cb(new Error('Недопустимый тип файла. Разрешены: PDF, DOC/DOCX, XLS/XLSX, PPT/PPTX, TXT, CSV, JSON, ZIP, код (.py, .js, .ts, .html, .css), а также аудио (M4A/AAC/MP3/OGG/OPUS/WAV)'));
};

// Лимит размера файла для загрузки в чат (100 MB — защита от DoS: файл хранится в памяти до загрузки в облако)
const MAX_FILE_SIZE_BYTES = 100 * 1024 * 1024;

export const uploadFile = multer({
  storage,
  limits: {
    fileSize: MAX_FILE_SIZE_BYTES,
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
    originalName: sanitizeOriginalName(file.originalname) || fileName,
    size: file.size || file.buffer.length,
    mime: file.mimetype || 'application/octet-stream',
  };
};

export const deleteFile = async (fileUrl) => {
  await deleteFromYandex(fileUrl);
};

