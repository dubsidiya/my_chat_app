export const ACCOUNT_DELETE_BLOCKED_MESSAGE =
  'Нельзя удалить аккаунт с занятиями или оплатами. Данные сохранятся. Выйдите из аккаунта или обратитесь к администратору.';

const FOOTPRINT_KEYS = [
  'students_created',
  'teacher_links',
  'lessons_created',
  'transactions_created',
  'reports_created',
  'salary_rows',
];

export const accountingFootprintBlocksDelete = (row) => {
  if (!row || typeof row !== 'object') return false;
  return FOOTPRINT_KEYS.some((key) => Number(row[key]) > 0);
};

export const loadAccountingFootprint = async (db, userId) => {
  const res = await db.query(
    `SELECT
       (SELECT COUNT(*)::int FROM students WHERE created_by = $1) AS students_created,
       (SELECT COUNT(*)::int FROM teacher_students WHERE teacher_id = $1) AS teacher_links,
       (SELECT COUNT(*)::int FROM lessons WHERE created_by = $1) AS lessons_created,
       (SELECT COUNT(*)::int FROM transactions WHERE created_by = $1) AS transactions_created,
       (SELECT COUNT(*)::int FROM reports WHERE created_by = $1) AS reports_created,
       (SELECT COUNT(*)::int FROM teacher_balance_transactions WHERE teacher_id = $1) AS salary_rows`,
    [userId]
  );
  return res.rows[0] || {
    students_created: 0,
    teacher_links: 0,
    lessons_created: 0,
    transactions_created: 0,
    reports_created: 0,
    salary_rows: 0,
  };
};
