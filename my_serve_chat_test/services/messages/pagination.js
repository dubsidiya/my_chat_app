export const parseLimit = (raw, { defaultValue = 50, min = 1, max = 200 } = {}) => {
  const parsed = Number.parseInt(raw, 10);
  const value = Number.isFinite(parsed) ? parsed : defaultValue;
  return Math.min(Math.max(value, min), max);
};

export const parseOffset = (raw, { defaultValue = 0, min = 0 } = {}) => {
  const parsed = Number.parseInt(raw, 10);
  const value = Number.isFinite(parsed) ? parsed : defaultValue;
  return Math.max(value, min);
};

export const parseOptionalInt = (raw) => {
  if (raw === undefined || raw === null || String(raw).trim().length === 0) return null;
  const parsed = Number.parseInt(String(raw), 10);
  return Number.isFinite(parsed) ? parsed : null;
};
