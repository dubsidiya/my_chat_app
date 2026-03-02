export const DEFAULT_USER_TIMEZONE = 'Europe/Moscow';

export const normalizeTimeZone = (value) => {
  const tz = (value || '').toString().trim();
  if (!tz) return null;
  try {
    // Бросает RangeError для некорректных IANA timezone.
    new Intl.DateTimeFormat('en-US', { timeZone: tz }).format(new Date());
    return tz;
  } catch (_) {
    return null;
  }
};

export const getDateInTimeZoneISO = (timeZone, date = new Date()) => {
  const tz = normalizeTimeZone(timeZone) || DEFAULT_USER_TIMEZONE;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const byType = {};
  for (const p of parts) {
    byType[p.type] = p.value;
  }
  return `${byType.year}-${byType.month}-${byType.day}`;
};

export const getUserTimeZone = async (client, userId) => {
  try {
    const r = await client.query(
      'SELECT timezone FROM users WHERE id = $1 LIMIT 1',
      [userId]
    );
    const fromDb = r.rows[0]?.timezone;
    return normalizeTimeZone(fromDb) || DEFAULT_USER_TIMEZONE;
  } catch (error) {
    if (error?.code === '42703' && String(error?.message || '').includes('timezone')) {
      return DEFAULT_USER_TIMEZONE;
    }
    throw error;
  }
};
