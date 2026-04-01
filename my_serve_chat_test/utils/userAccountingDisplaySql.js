/**
 * Фрагменты SQL: «как показывать пользователя в учёте/бухгалтерии».
 * Приоритет: display_name (ник/ФИО из профиля), иначе email (логин).
 */

/** Для обязательной строки (уроки, списки преподов). */
export const sqlUserAccountingName = (alias = 'u') =>
  `COALESCE(NULLIF(TRIM(COALESCE(${alias}.display_name, '')), ''), ${alias}.email, '(unknown)')`;

/** Для LEFT JOIN без пользователя — без заглушки. */
export const sqlUserAccountingNameOrEmpty = (alias = 'u') =>
  `COALESCE(NULLIF(TRIM(COALESCE(${alias}.display_name, '')), ''), ${alias}.email, '')`;
