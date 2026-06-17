import { DEFAULT_USER_TIMEZONE, normalizeTimeZone } from '../../utils/timezone.js';

export const serializeReportDate = (value) => {
  if (!value) return '';
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed.length >= 10) return trimmed.slice(0, 10);
    return trimmed;
  }
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
};

export const serializeTimestampIso = (value) => {
  if (!value) return null;
  if (value instanceof Date) return value.toISOString();
  const s = String(value).trim();
  if (!s) return null;
  if (/[zZ]|[+-]\d{2}:?\d{2}$/.test(s)) return s;
  const normalized = s.includes('T') ? s : s.replace(' ', 'T');
  return normalized.endsWith('Z') ? normalized : `${normalized}Z`;
};

/** Нормализует строку отчёта для JSON (дата + formation_label с SQL). */
export const serializeReportRow = (row) => {
  if (!row) return row;
  const reportDate = row.report_date_text
    ? String(row.report_date_text).slice(0, 10)
    : serializeReportDate(row.report_date);
  const out = { ...row };
  out.report_date = reportDate;
  if (row.formation_label != null) {
    out.formation_label = String(row.formation_label);
  }
  out.created_at = serializeTimestampIso(row.created_at);
  if (row.updated_at != null) {
    out.updated_at = serializeTimestampIso(row.updated_at);
  }
  delete out.report_date_text;
  return out;
};

export const serializeReportRows = (rows) =>
  Array.isArray(rows) ? rows.map((row) => serializeReportRow(row)) : [];
