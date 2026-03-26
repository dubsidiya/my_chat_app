import { parseLimit, parseOptionalInt } from '../../services/messages/pagination.js';

export const validateSearchQuery = ({ q, limit, before }) => {
  const text = (q || '').toString().trim();
  if (text.length > 100) {
    return { error: 'Слишком длинный запрос' };
  }

  const parsedLimit = parseLimit(limit, { defaultValue: 300, min: 1, max: 500 });
  const parsedBefore = parseOptionalInt(before);
  if (before != null && String(before).trim() !== '' && parsedBefore === null) {
    return { error: 'Некорректный параметр before' };
  }

  return { q: text, limit: parsedLimit, before: parsedBefore, error: null };
};

export const validateAroundQuery = ({ messageId, limit }) => {
  const parsedMessageId = parseOptionalInt(messageId);
  if (parsedMessageId === null) {
    return { error: 'Некорректный messageId' };
  }
  const parsedLimit = parseLimit(limit, { defaultValue: 50, min: 10, max: 200 });
  return { messageId: parsedMessageId, limit: parsedLimit, error: null };
};
