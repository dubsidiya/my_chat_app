/**
 * CSV-ячейки для выгрузок бухгалтерии.
 * Кавычки по RFC 4180 + нейтрализация формул Excel (= + - @ tab CR).
 */

const PLAIN_NUMBER = /^-?\d+(\.\d+)?$/;
const FORMULA_START = new Set(['=', '+', '-', '@', '\t', '\r']);

export const neutralizeCsvFormula = (value) => {
  const s = value == null ? '' : String(value);
  if (s === '' || PLAIN_NUMBER.test(s)) return s;
  const firstMeaningful = s.replace(/^[\s\u00a0]+/, '').charAt(0);
  if (FORMULA_START.has(firstMeaningful)) return `'${s}`;
  return s;
};

export const escapeCsvCell = (value) => {
  if (value == null) return '';
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  const s = neutralizeCsvFormula(String(value));
  if (s.includes('"') || s.includes(',') || s.includes('\n') || s.includes('\r')) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
};

export const asCsv = (rows) =>
  (rows || []).map((row) => (row || []).map(escapeCsvCell).join(',')).join('\n');
