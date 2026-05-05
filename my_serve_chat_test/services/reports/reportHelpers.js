import { getDateInTimeZoneISO, getUserTimeZone } from '../../utils/timezone.js';

const MAX_SLOTS_PER_DAY = 10;
const MAX_STUDENTS_PER_SLOT = 4;
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const LESSON_STATUSES = new Set(['attended', 'missed', 'makeup', 'cancel_same_day']);

export const parseReportContent = (content) => {
  const lines = content.split('\n').map((line) => line.trim()).filter((line) => line);
  const lessons = [];

  let startIndex = 0;
  if (lines.length > 0 && /^\d+\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)/i.test(lines[0])) {
    startIndex = 1;
  }

  for (let i = startIndex; i < lines.length; i++) {
    const line = lines[i];
    if (!line) continue;

    const timePattern = /^(\d{1,2})-(\d{1,2})\s+(.+)$/;
    const timeMatch = line.match(timePattern);
    if (!timeMatch) continue;

    const startTime = timeMatch[1];
    const endTime = timeMatch[2];
    const restOfLine = timeMatch[3];

    const isCancelled = /\?{3,}/.test(restOfLine);
    const cleanLine = restOfLine.replace(/\?{3,}/g, '').trim();
    const students = cleanLine.split('/').map((s) => s.trim()).filter((s) => s);

    for (const studentStr of students) {
      const studentPattern = /^(.+?)\s+(\d+)\.(\d+)\s*$/;
      const studentMatch = studentStr.match(studentPattern);
      if (!studentMatch) continue;

      const studentName = studentMatch[1].trim();
      const priceInt = parseInt(studentMatch[2], 10);
      const priceDec = parseInt(studentMatch[3], 10);
      const price = priceInt * 1000 + priceDec * 100;

      if (studentName && price > 0) {
        lessons.push({
          studentName,
          price,
          timeStart: startTime,
          timeEnd: endTime,
          status: isCancelled ? 'cancel_same_day' : 'attended',
          originLessonId: null,
          notes: isCancelled ? 'Отмена в день проведения' : null,
        });
      }
    }
  }

  return lessons;
};

const isValidTimeHHMM = (t) => typeof t === 'string' && /^([01]?\d|2[0-3]):[0-5]\d$/.test(t.trim());

export const toMinutes = (t) => {
  const [h, m] = t.split(':').map((x) => parseInt(x, 10));
  return h * 60 + m;
};

const formatPriceK = (priceRub) => {
  const n = typeof priceRub === 'string' ? parseFloat(priceRub) : priceRub;
  if (!Number.isFinite(n)) return '0.0';
  return (n / 1000).toFixed(1);
};

export const buildReportContentFromSlots = (reportDate, slots, studentIdToName) => {
  const lines = [];
  lines.push(String(reportDate));
  lines.push('');
  for (const slot of slots) {
    const start = slot.timeStart;
    const end = slot.timeEnd;
    const studentParts = (slot.students || []).map((s) => {
      const name = studentIdToName.get(s.studentId) || `ID:${s.studentId}`;
      return `${name} ${formatPriceK(s.price)}`;
    });
    lines.push(`${start}-${end} ${studentParts.join(' / ')}`.trim());
  }
  return lines.join('\n').trim();
};

export const normalizeSlots = (rawSlots) => {
  if (!Array.isArray(rawSlots)) return [];
  return rawSlots
    .map((s) => ({
      timeStart: typeof s?.timeStart === 'string' ? s.timeStart.trim() : '',
      timeEnd: typeof s?.timeEnd === 'string' ? s.timeEnd.trim() : '',
      students: Array.isArray(s?.students) ? s.students : [],
    }))
    .filter((s) => s.timeStart && s.timeEnd);
};

export const validateSlots = (slots) => {
  if (!Array.isArray(slots) || slots.length === 0) {
    return 'Нужно добавить хотя бы одно занятие';
  }
  if (slots.length > MAX_SLOTS_PER_DAY) {
    return `Максимум ${MAX_SLOTS_PER_DAY} занятий в день`;
  }
  for (const slot of slots) {
    if (!isValidTimeHHMM(slot.timeStart) || !isValidTimeHHMM(slot.timeEnd)) {
      return 'Время должно быть в формате ЧЧ:ММ';
    }
    const a = toMinutes(slot.timeStart);
    const b = toMinutes(slot.timeEnd);
    if (b <= a) return 'Время окончания должно быть позже времени начала';
    if (!Array.isArray(slot.students) || slot.students.length === 0) {
      return 'В каждом времени должен быть выбран хотя бы один ученик';
    }
    if (slot.students.length > MAX_STUDENTS_PER_SLOT) {
      return `В одном времени максимум ${MAX_STUDENTS_PER_SLOT} ученика`;
    }
    const ids = slot.students.map((x) => x?.studentId).filter(Boolean);
    const unique = new Set(ids);
    if (ids.length !== unique.size) {
      return 'В одном времени нельзя выбрать одного и того же ученика дважды';
    }
    for (const st of slot.students) {
      const id = parseInt(st?.studentId, 10);
      const price = typeof st?.price === 'string' ? parseFloat(st.price) : st?.price;
      const status = typeof st?.status === 'string' ? st.status.trim() : 'attended';
      const originLessonId = st?.originLessonId == null ? null : parseInt(st.originLessonId, 10);
      if (!id || Number.isNaN(id)) return 'Некорректный ученик в занятии';
      if (!Number.isFinite(price) || price <= 0) return 'Укажите стоимость для каждого ученика';
      if (!LESSON_STATUSES.has(status)) return 'Некорректный статус занятия';
      if (originLessonId != null && Number.isNaN(originLessonId)) return 'Некорректный originLessonId';
    }
  }
  return null;
};

export const resolveChargeableByStatus = async (client, { studentId, status, teacherId }) => {
  if (status === 'missed') return false;
  if (status === 'makeup') return true;
  if (status !== 'cancel_same_day') return true;

  await client.query(
    `SELECT id
     FROM students
     WHERE id = $1
     FOR UPDATE`,
    [studentId]
  );

  const freeUsed = await client.query(
    `SELECT id
     FROM lessons
     WHERE student_id = $1
       AND created_by = $2
       AND status = 'cancel_same_day'
       AND is_chargeable = false
     LIMIT 1`,
    [studentId, teacherId]
  );
  return freeUsed.rows.length > 0;
};

export const isValidISODate = (value) => typeof value === 'string' && ISO_DATE_RE.test(value);

export const getTodayByUserTimezone = async (db, userId) => {
  const tz = await getUserTimeZone(db, userId);
  return { tz, todayIso: getDateInTimeZoneISO(tz) };
};
