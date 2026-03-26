import { isValidISODate } from '../../services/reports/reportHelpers.js';

export const MAX_REPORT_CONTENT_LENGTH = 200000;

export const validateMonthlySalaryQuery = ({ year, month }) => {
  const parsedYear = parseInt(year, 10);
  const parsedMonth = parseInt(month, 10);
  if (!Number.isFinite(parsedYear) || !Number.isFinite(parsedMonth) || parsedMonth < 1 || parsedMonth > 12) {
    return { error: 'Укажите год и месяц: year, month (1–12)' };
  }
  return { year: parsedYear, month: parsedMonth };
};

export const validateReportInput = ({ reportDate, content, hasSlots }) => {
  if (!reportDate || (!content && !hasSlots)) {
    return { error: 'Дата обязательна. Укажите либо content, либо slots' };
  }
  if (content != null && String(content).length > MAX_REPORT_CONTENT_LENGTH) {
    return { error: `Текст отчёта не более ${MAX_REPORT_CONTENT_LENGTH} символов` };
  }
  if (!isValidISODate(reportDate)) {
    return { error: 'report_date должен быть в формате YYYY-MM-DD' };
  }
  return { error: null };
};
