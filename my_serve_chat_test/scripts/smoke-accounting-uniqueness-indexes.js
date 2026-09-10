/**
 * H13/H14: уникальность report_lessons и одно списание на занятие.
 * Фикстуры в транзакции, в конце ROLLBACK.
 *
 * Run: node scripts/smoke-accounting-uniqueness-indexes.js
 */
import pool from '../db.js';

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

const run = async () => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const stamp = Date.now();
    const userRes = await client.query(
      `INSERT INTO users (email, password)
       VALUES ($1, 'smoke_hash')
       RETURNING id`,
      [`smoke-h13-${stamp}@test.local`]
    );
    const teacherId = userRes.rows[0].id;
    const studentRes = await client.query(
      `INSERT INTO students (name, created_by)
       VALUES ($1, $2)
       RETURNING id`,
      [`smoke-h13-${stamp}`, teacherId]
    );
    const studentId = studentRes.rows[0].id;

    const reportA = await client.query(
      `INSERT INTO reports (report_date, content, created_by)
       VALUES ('2026-01-03', 'report-a', $1)
       RETURNING id`,
      [teacherId]
    );
    const reportB = await client.query(
      `INSERT INTO reports (report_date, content, created_by)
       VALUES ('2026-01-04', 'report-b', $1)
       RETURNING id`,
      [teacherId]
    );
    const lessonRes = await client.query(
      `INSERT INTO lessons (student_id, lesson_date, lesson_time, price, created_by)
       VALUES ($1, '2026-01-03', '11:00', 1000, $2)
       RETURNING id`,
      [studentId, teacherId]
    );
    const lessonId = lessonRes.rows[0].id;
    await client.query(
      `INSERT INTO report_lessons (report_id, lesson_id) VALUES ($1, $2)`,
      [reportB.rows[0].id, lessonId]
    );

    await client.query('SAVEPOINT sp_old_insert');
    let insertCode = null;
    try {
      await client.query(
        `INSERT INTO report_lessons (report_id, lesson_id)
         SELECT $1, rl.lesson_id
         FROM report_lessons rl
         WHERE rl.report_id = $2
         ON CONFLICT (report_id, lesson_id) DO NOTHING`,
        [reportA.rows[0].id, reportB.rows[0].id]
      );
    } catch (error) {
      insertCode = error?.code || 'unknown';
      await client.query('ROLLBACK TO SAVEPOINT sp_old_insert');
    }
    assert(
      insertCode === '23505',
      `INSERT занятия во второй отчёт при uq_report_lessons_lesson_id должен дать 23505, получили ${insertCode}`
    );

    const tx1 = await client.query(
      `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
       VALUES ($1, 1000, 'lesson', 'smoke-h14-a', $2, $3)
       RETURNING id`,
      [studentId, lessonId, teacherId]
    );
    const tx2 = await client.query(
      `INSERT INTO transactions (student_id, amount, type, description, lesson_id, created_by)
       VALUES ($1, 1000, 'lesson', 'smoke-h14-b', $2, $3)
       RETURNING id`,
      [studentId, lessonId, teacherId]
    );
    await client.query(
      `INSERT INTO transactions (student_id, amount, type, description, created_by)
       VALUES ($1, 5000, 'deposit', 'smoke-h14-deposit', $2)`,
      [studentId, teacherId]
    );
    await client.query(`
      DELETE FROM transactions
      WHERE id IN (
        SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (PARTITION BY lesson_id ORDER BY id) AS rn
          FROM transactions
          WHERE type = 'lesson' AND lesson_id IS NOT NULL
        ) ranked
        WHERE ranked.rn > 1
      )
    `);
    const lessonTx = await client.query(
      `SELECT id FROM transactions
       WHERE lesson_id = $1 AND type = 'lesson'
       ORDER BY id`,
      [lessonId]
    );
    assert(lessonTx.rowCount === 1, `должно остаться одно списание, получили ${lessonTx.rowCount}`);
    assert(
      Number(lessonTx.rows[0].id) === Number(tx1.rows[0].id),
      'должно остаться более раннее списание'
    );
    assert(Number(lessonTx.rows[0].id) !== Number(tx2.rows[0].id), 'второе списание должно уйти');
    const depositLeft = await client.query(
      `SELECT COUNT(*)::int AS c FROM transactions
       WHERE student_id = $1 AND type = 'deposit' AND description = 'smoke-h14-deposit'`,
      [studentId]
    );
    assert(depositLeft.rows[0].c === 1, 'депозит не должен удалиться');

    await client.query('ROLLBACK');
    console.log('✅ smoke-accounting-uniqueness-indexes: ok');
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
};

run().catch((error) => {
  console.error('❌ smoke-accounting-uniqueness-indexes failed:', error?.message || error);
  process.exit(1);
});
