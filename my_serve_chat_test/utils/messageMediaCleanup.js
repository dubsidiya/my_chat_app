import { deleteFromYandex } from './yandexStorage.js';

const pickNonEmpty = (value) => {
  const s = String(value || '').trim();
  return s.length > 0 ? s : null;
};

export const collectMessageMediaUrls = (rows) => {
  const urls = new Set();
  for (const row of rows || []) {
    const imageUrl = pickNonEmpty(row?.image_url);
    const originalImageUrl = pickNonEmpty(row?.original_image_url);
    const fileUrl = pickNonEmpty(row?.file_url);
    if (imageUrl) urls.add(imageUrl);
    if (originalImageUrl) urls.add(originalImageUrl);
    if (fileUrl) urls.add(fileUrl);
  }
  return [...urls];
};

export const cleanupMessageMediaUrls = async (urls, { label = 'media-cleanup' } = {}) => {
  const uniqueUrls = [...new Set((urls || []).map(pickNonEmpty).filter(Boolean))];
  if (uniqueUrls.length === 0) {
    return { attempted: 0 };
  }

  for (const url of uniqueUrls) {
    try {
      await deleteFromYandex(url);
    } catch (error) {
      // deleteFromYandex уже best-effort, но страхуемся от неожиданных ошибок.
      console.error(`${label}: failed to cleanup media url`, { url, error: error?.message || error });
    }
  }

  return { attempted: uniqueUrls.length };
};

