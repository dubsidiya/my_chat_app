/**
 * Скрытый профиль работы преподавателя и индекс качества.
 *
 * ВНИМАНИЕ: данные из этого модуля используются ТОЛЬКО в admin-выгрузке
 * (`/admin/accounting/export-xlsx`, JSON формата `/admin/accounting/export`),
 * которая закрыта `requireSuperuser`. Никогда не отдавайте поля
 * `qualityIndex`/`qualityFactors`/`workProfile` в teacher-facing API
 * (reports, students, lessons), это нарушит контракт «скрытой оценки».
 *
 * Оценка объяснимая (набор взвешенных правил, без ML) и сравнивает
 * преподавателя в первую очередь с его собственным историческим графиком.
 */

const median = (arr) => {
  if (!arr || arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[mid - 1] + sorted[mid]) / 2
    : sorted[mid];
};

const percentile = (arr, p) => {
  if (!arr || arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.floor(p * sorted.length)));
  return sorted[idx];
};

const toIsoDate = (v) => {
  if (!v) return '';
  if (typeof v === 'string') return v.length >= 10 ? v.slice(0, 10) : v;
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  try {
    return new Date(v).toISOString().slice(0, 10);
  } catch (_) {
    return '';
  }
};

const subtractDays = (isoDate, days) => {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
};

const dowOf = (isoDate) => new Date(`${isoDate}T00:00:00Z`).getUTCDay();

const enumerateDates = (from, to) => {
  const out = [];
  const cur = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  while (cur <= end) {
    out.push(cur.toISOString().slice(0, 10));
    cur.setUTCDate(cur.getUTCDate() + 1);
  }
  return out;
};

/**
 * Строит профиль работы преподавателя по lookbackDays истории ДО anchorDate.
 * Учитывает только состоявшиеся chargeable-занятия (attended/makeup) — это
 * подходит как proxy для «обычного графика».
 */
export const computeTeacherWorkProfile = async (pool, teacherId, { lookbackDays = 84, anchorDate } = {}) => {
  if (!anchorDate) {
    throw Object.assign(new Error('anchorDate is required'), { statusCode: 500 });
  }
  const from = subtractDays(anchorDate, lookbackDays);
  const to = subtractDays(anchorDate, 1);

  const res = await pool.query(
    `SELECT lesson_date::text AS lesson_date,
            EXTRACT(DOW FROM lesson_date)::int AS dow,
            COUNT(*)::int AS lessons_per_day
     FROM lessons
     WHERE created_by = $1
       AND lesson_date >= $2::date
       AND lesson_date <= $3::date
       AND COALESCE(is_chargeable, true) = true
       AND status IN ('attended', 'makeup')
     GROUP BY lesson_date
     ORDER BY lesson_date`,
    [teacherId, from, to]
  );

  const perDayByDow = new Map();
  for (let i = 0; i < 7; i += 1) perDayByDow.set(i, []);

  let totalLessons = 0;
  for (const row of res.rows) {
    const dow = Number.isInteger(row.dow) ? row.dow : dowOf(row.lesson_date);
    perDayByDow.get(dow).push(row.lessons_per_day);
    totalLessons += row.lessons_per_day;
  }

  const totalWeeks = Math.max(1, Math.floor(lookbackDays / 7));
  const presenceThreshold = Math.max(1, Math.ceil(totalWeeks * 0.3));

  const typicalDows = [];
  const dowMedians = {};
  for (let dow = 0; dow < 7; dow += 1) {
    const counts = perDayByDow.get(dow);
    if (counts.length >= presenceThreshold) {
      typicalDows.push(dow);
      dowMedians[dow] = median(counts);
    }
  }

  const allWorkDayCounts = [];
  for (const dow of typicalDows) {
    allWorkDayCounts.push(...perDayByDow.get(dow));
  }

  const sampleDays = res.rows.length;
  const hasEnoughData = sampleDays >= 8 && typicalDows.length >= 1 && totalLessons >= 16;

  return {
    teacherId,
    lookbackDays,
    anchorDate,
    historyFrom: from,
    historyTo: to,
    typicalDows: typicalDows.sort((a, b) => a - b),
    dowMedians,
    medianPerWorkDay: median(allWorkDayCounts),
    p25: percentile(allWorkDayCounts, 0.25),
    p75: percentile(allWorkDayCounts, 0.75),
    sampleDays,
    totalLessons,
    hasEnoughData,
  };
};

/**
 * Сколько уроков ожидается у преподавателя в [from, to] на основе его профиля.
 * Возвращает 0, если профиль ненадёжен (мало истории) — чтобы не штрафовать новичков.
 */
export const expectedLessonsInPeriod = (profile, from, to) => {
  if (!profile || !profile.hasEnoughData || !profile.medianPerWorkDay) return 0;
  const typical = new Set(profile.typicalDows);
  let expected = 0;
  for (const d of enumerateDates(from, to)) {
    if (typical.has(dowOf(d))) {
      expected += profile.medianPerWorkDay;
    }
  }
  return Math.round(expected * 10) / 10;
};

/**
 * Считает пропуски и бесплатные отмены преподавателя в его «типичные» дни недели
 * за период. Это маркер срыва не в выходной, а в день, когда обычно идут занятия.
 */
export const countMissedOnTypicalDow = (lessonsRows, teacherId, profile, period) => {
  if (!profile || !profile.hasEnoughData) return 0;
  if (!Array.isArray(lessonsRows) || !period) return 0;
  const typical = new Set(profile.typicalDows);
  let count = 0;
  for (const l of lessonsRows) {
    const tid = l.teacher_id ?? l.created_by;
    if (tid !== teacherId) continue;
    const date = toIsoDate(l.lesson_date);
    if (!date || date < period.from || date > period.to) continue;
    const status = (l.status || 'attended').toString();
    const isFreeCancel = status === 'cancel_same_day' && l.is_chargeable !== true;
    if (status !== 'missed' && !isFreeCancel) continue;
    if (typical.has(dowOf(date))) count += 1;
  }
  return count;
};

const pushFactor = (factors, code, label, delta) => {
  if (delta === 0) return 0;
  factors.push({ code, label, delta, impact: delta < 0 ? 'negative' : 'positive' });
  return -delta;
};

/**
 * Скрытый индекс качества работы преподавателя за период (0..100).
 * Объяснимая формула: набор взвешенных правил, каждое добавляет фактор
 * в `qualityFactors` с понятной подписью. Используется только в admin-выгрузке.
 */
export const computeTeacherQuality = (stats, profile) => {
  if (!profile || !profile.hasEnoughData) {
    return { qualityIndex: null, qualityFactors: [], reason: 'insufficient_history' };
  }

  const factors = [];
  let penalty = 0;

  if (typeof stats.kpiPercent === 'number' && stats.kpiPercent < 80) {
    const p = Math.min(40, Math.round((80 - stats.kpiPercent) * 0.6));
    penalty += pushFactor(factors, 'kpi_low', `Низкий КПД (${stats.kpiPercent}%)`, -p);
  }

  const openDebt = Number(stats.openMakeupDebtCount || 0);
  if (openDebt > 0) {
    const p = Math.min(25, openDebt * 3);
    penalty += pushFactor(factors, 'open_debt', `Открытые долги отработки (${openDebt})`, -p);
  }

  const totalCh = Number(stats.totalChargeable || 0);
  const lateAmt = Number(stats.lateAmount || 0);
  if (totalCh > 0 && lateAmt > 0) {
    const share = lateAmt / totalCh;
    const p = Math.min(20, Math.round(share * 50));
    if (p > 0) {
      penalty += pushFactor(
        factors,
        'late_reports',
        `Поздние отчёты (${Math.round(share * 100)}% дохода)`,
        -p
      );
    }
  }

  const noRep = Number(stats.noReportAmount || 0);
  if (totalCh > 0 && noRep > 0) {
    const share = noRep / totalCh;
    const p = Math.min(15, Math.round(share * 40));
    if (p > 0) {
      penalty += pushFactor(
        factors,
        'no_report',
        `Занятия без отчёта (${Math.round(share * 100)}%)`,
        -p
      );
    }
  }

  const expected = Number(stats.expectedLessons || 0);
  const actual = Number(stats.actualLessons || 0);
  if (expected > 2) {
    const ratio = actual / expected;
    if (ratio < 0.5) {
      penalty += pushFactor(
        factors,
        'schedule_drop',
        `Сильное падение нагрузки (${Math.round(ratio * 100)}% от обычного)`,
        -25
      );
    } else if (ratio < 0.7) {
      penalty += pushFactor(
        factors,
        'schedule_drop',
        `Падение нагрузки (${Math.round(ratio * 100)}% от обычного)`,
        -10
      );
    }
  }

  const missedDow = Number(stats.missedOnTypicalDowCount || 0);
  if (missedDow > 0) {
    const p = Math.min(20, missedDow * 4);
    penalty += pushFactor(
      factors,
      'missed_on_typical_dow',
      `Пропуски в типичные дни (${missedDow})`,
      -p
    );
  }

  factors.sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta));
  const qualityIndex = Math.max(0, Math.min(100, 100 - penalty));
  return { qualityIndex, qualityFactors: factors, reason: null };
};

export const __testing = { median, percentile, dowOf, enumerateDates };
