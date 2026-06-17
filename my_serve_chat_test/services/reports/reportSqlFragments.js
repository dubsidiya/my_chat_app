/** IANA timezone автора отчёта (fallback Europe/Moscow). */
export const reportOwnerTimezoneExpr = (userAlias = 'u') =>
  `COALESCE(NULLIF(trim(${userAlias}.timezone), ''), 'Europe/Moscow')`;

/** Календарная дата отчёта без сдвига по TZ. */
export const sqlReportDateText = (reportAlias = 'r') =>
  `to_char(${reportAlias}.report_date, 'YYYY-MM-DD') AS report_date_text`;

/**
 * Время сдачи отчёта в TZ преподавателя (для UI «Сформирован»).
 * created_at в БД — TIMESTAMP WITHOUT TIME ZONE в TZ сервера БД.
 */
export const sqlFormationLabel = (reportAlias = 'r', userAlias = 'u') => `
  to_char(
    ((${reportAlias}.created_at AT TIME ZONE current_setting('TIMEZONE'))
      AT TIME ZONE ${reportOwnerTimezoneExpr(userAlias)}),
    'DD.MM.YYYY HH24:MI'
  ) AS formation_label`;
