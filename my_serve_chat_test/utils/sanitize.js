/**
 * Санитизация строк для отображения (ник, имя чата, папки).
 * Удаляет управляющие символы и zero-width, защита от XSS и сломанного отображения.
 */
const CONTROL_AND_ZEROWIDTH = /[\x00-\x1F\x7F\u200B-\u200D\uFEFF\u2060]/g;

export function sanitizeForDisplay(str, maxLength = 255) {
  if (str == null || typeof str !== 'string') return '';
  const trimmed = str.trim().replace(CONTROL_AND_ZEROWIDTH, '');
  if (maxLength > 0 && trimmed.length > maxLength) return trimmed.slice(0, maxLength);
  return trimmed;
}

/**
 * Санитизация текста сообщения: убираем null-байты и опасные управляющие символы,
 * сохраняем переводы строк и табуляцию.
 */
const MESSAGE_UNSAFE = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g;

export function sanitizeMessageContent(str) {
  if (str == null) return '';
  if (typeof str !== 'string') return String(str);
  return str.replace(MESSAGE_UNSAFE, '');
}

const MAX_SAFE_INT = Number.MAX_SAFE_INTEGER;

/**
 * Парсинг положительного целого ID из params/query.
 * Возвращает число или null, если значение невалидно (не число, <= 0, NaN, переполнение).
 */
export function parsePositiveInt(value, radix = 10) {
  if (value == null) return null;
  const n = typeof value === 'number' ? value : parseInt(value, radix);
  return Number.isFinite(n) && n > 0 && n <= MAX_SAFE_INT ? n : null;
}
