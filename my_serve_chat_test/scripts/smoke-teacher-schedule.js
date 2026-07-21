/**
 * Smoke-check teacher schedule / placement planner logic.
 *
 * Run: node scripts/smoke-teacher-schedule.js
 */
import {
  median,
  percentile,
  placementStatus,
  loadLevelForCount,
  getTeacherPlacementPlan,
  getTeacherScheduleHeatmap,
  getTeacherScheduleOverview,
} from '../controllers/teacherScheduleController.js';
import pool from '../db.js';

const makeRes = () => ({
  statusCode: 200,
  body: null,
  status(code) {
    this.statusCode = code;
    return this;
  },
  json(payload) {
    this.body = payload;
    return this;
  },
});

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

const assertEq = (actual, expected, msg) => {
  if (actual !== expected) {
    throw new Error(`${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
};

const run = async () => {
  // --- pure helpers ---
  assertEq(median([1]), 1, 'median single');
  assertEq(median([1, 3]), 2, 'median even');
  assertEq(median([1, 2, 100]), 2, 'median odd resistant to peak');
  assertEq(percentile([1, 2, 3, 4], 0.75), 4, 'percentile p75 discrete');

  assertEq(placementStatus(1, 1, 2, 3, true), 'unstable', 'weeks_active < 2');
  assertEq(placementStatus(1, 4, 2, 3, false), 'unstable', 'non-typical day cannot be open');
  assertEq(placementStatus(1, 4, 2, 3, true), 'open', 'typical + low concurrency');
  assertEq(placementStatus(2, 4, 2, 3, true), 'limited', 'at high');
  assertEq(placementStatus(3, 4, 2, 3, true), 'full', 'at overload');

  // Overview threshold unit: cell totals [4,4] → p75=4; cell of 4 is normal, not overload
  const thrHigh = Math.max(2, percentile([4, 4], 0.75));
  const thrOver = Math.max(3, Math.ceil(thrHigh * 1.25));
  assertEq(loadLevelForCount(4, thrHigh, thrOver), 'high', 'cell total matches sample unit');
  assertEq(loadLevelForCount(8, thrHigh, thrOver), 'overload', 'double cell is overload');
  // Old bug would sample [4,4] from per-student and compare cell=8 → false overload at threshold 4/5
  // Fixed path samples cell totals so a cell of 4 is consistent with samples of 4.

  // --- DB fixtures (rollback) ---
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const stamp = Date.now();
    const userRes = await client.query(
      `INSERT INTO users (email, password)
       VALUES ($1, 'smoke_hash')
       RETURNING id`,
      [`smoke_sched_${stamp}@test.local`]
    );
    const teacherId = userRes.rows[0].id;

    const students = [];
    for (let i = 0; i < 4; i += 1) {
      const s = await client.query(
        `INSERT INTO students (name, created_by)
         VALUES ($1, $2)
         RETURNING id`,
        [`Smoke Student ${i + 1}`, teacherId]
      );
      students.push(s.rows[0].id);
    }

    // Four Mondays 10:00: different student each week (churn) + one cancel that must be ignored
    const mondays = ['2026-01-05', '2026-01-12', '2026-01-19', '2026-01-26'];
    for (let i = 0; i < mondays.length; i += 1) {
      await client.query(
        `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, status, is_chargeable, created_by)
         VALUES ($1, $2::date, '10:00', 60, 1000, 'attended', true, $3)`,
        [students[i], mondays[i], teacherId]
      );
    }
    await client.query(
      `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, status, is_chargeable, created_by)
       VALUES ($1, '2026-01-05'::date, '10:00', 60, 1000, 'cancel_same_day', false, $2)`,
      [students[0], teacherId]
    );

    // Sunday atypical slot (only 2 weeks) — should not become open even if low concurrency
    await client.query(
      `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, status, is_chargeable, created_by)
       VALUES ($1, '2026-01-04'::date, '12:00', 60, 1000, 'attended', true, $2),
              ($1, '2026-01-11'::date, '12:00', 60, 1000, 'attended', true, $2)`,
      [students[0], teacherId]
    );

    // Seed weekday history before the analysis period so Mon is typical (lookback from to=2026-01-31).
    for (let w = 0; w < 12; w += 1) {
      const d = new Date(Date.UTC(2025, 9, 6)); // Mon 2025-10-06
      d.setUTCDate(d.getUTCDate() + w * 7);
      const iso = d.toISOString().slice(0, 10);
      if (iso >= '2026-01-01') break;
      await client.query(
        `INSERT INTO lessons (student_id, lesson_date, lesson_time, duration_minutes, price, status, is_chargeable, created_by)
         VALUES ($1, $2::date, '10:00', 60, 1000, 'attended', true, $3)`,
        [students[0], iso, teacherId]
      );
    }

    // Temporarily swap pool query to use transaction client for controller calls
    const originalQuery = pool.query.bind(pool);
    pool.query = (...args) => client.query(...args);

    try {
      const heatRes = makeRes();
      await getTeacherScheduleHeatmap(
        {
          query: {
            from: '2026-01-01',
            to: '2026-01-31',
            teacher_id: String(teacherId),
          },
        },
        heatRes
      );
      assertEq(heatRes.statusCode, 200, 'heatmap status');
      const monCell = (heatRes.body?.cells || []).find(
        (c) => c.weekday === 1 && c.time_slot === '10:00'
      );
      assert(monCell, 'monday 10:00 cell');
      // 4 attended in Jan + cancels excluded; lookback seed is outside Jan period
      assertEq(monCell.count, 4, 'heatmap excludes cancel_same_day');

      const placeRes = makeRes();
      await getTeacherPlacementPlan(
        {
          query: {
            from: '2026-01-01',
            to: '2026-01-31',
            teacher_ids: String(teacherId),
          },
        },
        placeRes
      );
      assertEq(placeRes.statusCode, 200, 'placement status');
      const teacher = placeRes.body?.teachers?.[0];
      assert(teacher, 'placement teacher');
      const monSlot = (teacher.slots || []).find((s) => s.weekday === 1 && s.time_slot === '10:00');
      assert(monSlot, 'placement monday slot');
      // Churn: 4 distinct students over period, but median concurrency per week = 1
      assertEq(monSlot.students_count, 1, 'students_count is median concurrency not churn');
      assert(monSlot.students_peak >= 1, 'students_peak present');
      assertEq(monSlot.placement_status, 'open', 'churn must not mark full');

      const sunSlot = (teacher.slots || []).find((s) => s.weekday === 7 && s.time_slot === '12:00');
      assert(sunSlot, 'sunday slot');
      assertEq(sunSlot.placement_status, 'unstable', 'non-typical sunday not open');

      const overRes = makeRes();
      await getTeacherScheduleOverview(
        {
          query: {
            from: '2026-01-01',
            to: '2026-01-31',
            teacher_ids: String(teacherId),
          },
        },
        overRes
      );
      assertEq(overRes.statusCode, 200, 'overview status');
      assertEq(overRes.body?.insights?.gap_cells, 0, 'no synthetic cartesian gaps');
      const overCell = (overRes.body?.cells || []).find(
        (c) => c.weekday === 1 && c.time_slot === '10:00'
      );
      assert(overCell, 'overview monday cell');
      assertEq(overCell.total_count, 4, 'overview excludes cancels');
      assertEq(overCell.is_gap, false, 'existing cell is not gap');
    } finally {
      pool.query = originalQuery;
    }

    await client.query('ROLLBACK');
  } catch (e) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {
      /* ignore */
    }
    throw e;
  } finally {
    client.release();
  }

  console.log('smoke-teacher-schedule: OK');
  await pool.end();
};

run().catch(async (err) => {
  console.error('smoke-teacher-schedule: FAIL', err);
  try {
    await pool.end();
  } catch (_) {
    /* ignore */
  }
  process.exit(1);
});
