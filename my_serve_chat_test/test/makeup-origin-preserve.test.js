import assert from 'node:assert/strict';
import test from 'node:test';

import { isMakeupOriginUniqueViolation, matchPreservedMakeupOrigins } from '../utils/makeupDebts.js';

test('matchPreservedMakeupOrigins keeps miss id when student/status/time match', () => {
  const oldLessons = [
    { id: 10, student_id: 1, status: 'missed', lesson_time: '09:00:00' },
    { id: 11, student_id: 1, status: 'attended', lesson_time: '10:00:00' },
  ];
  const parsedLessons = [
    { studentId: 1, status: 'missed', lessonTimeHHMM: '09:00' },
    { studentId: 1, status: 'attended', lessonTimeHHMM: '10:00' },
  ];
  const { preservedByParsedIndex, unmatched } = matchPreservedMakeupOrigins({
    oldLessons,
    parsedLessons,
    referencedOriginIds: [10],
  });
  assert.equal(unmatched.length, 0);
  assert.equal(preservedByParsedIndex.get(0)?.id, 10);
  assert.equal(preservedByParsedIndex.has(1), false);
});

test('matchPreservedMakeupOrigins unique-fallback matches when only time changed', () => {
  const { preservedByParsedIndex, unmatched } = matchPreservedMakeupOrigins({
    oldLessons: [{ id: 44, student_id: 7, status: 'missed', lesson_time: '09:00:00' }],
    parsedLessons: [{ studentId: 7, status: 'missed', lessonTimeHHMM: '09:15' }],
    referencedOriginIds: [44],
  });
  assert.equal(unmatched.length, 0);
  assert.equal(preservedByParsedIndex.get(0)?.id, 44);
});

test('matchPreservedMakeupOrigins rejects removing an already made-up miss', () => {
  const { preservedByParsedIndex, unmatched } = matchPreservedMakeupOrigins({
    oldLessons: [{ id: 44, student_id: 7, status: 'missed', lesson_time: '09:00:00' }],
    parsedLessons: [{ studentId: 7, status: 'attended', lessonTimeHHMM: '09:00' }],
    referencedOriginIds: [44],
  });
  assert.equal(preservedByParsedIndex.size, 0);
  assert.equal(unmatched.length, 1);
  assert.equal(unmatched[0].id, 44);
});

test('isMakeupOriginUniqueViolation matches only the makeup origin index', () => {
  assert.equal(
    isMakeupOriginUniqueViolation({ code: '23505', constraint: 'ux_lessons_makeup_origin' }),
    true
  );
  assert.equal(
    isMakeupOriginUniqueViolation({ code: '23505', constraint: 'ux_lessons_owner_student_date_time' }),
    false
  );
});

test('matchPreservedMakeupOrigins does not guess when two misses share a student', () => {
  const { unmatched } = matchPreservedMakeupOrigins({
    oldLessons: [
      { id: 1, student_id: 7, status: 'missed', lesson_time: '09:00:00' },
      { id: 2, student_id: 7, status: 'missed', lesson_time: '11:00:00' },
    ],
    parsedLessons: [
      { studentId: 7, status: 'missed', lessonTimeHHMM: '10:00' },
      { studentId: 7, status: 'missed', lessonTimeHHMM: '12:00' },
    ],
    referencedOriginIds: [1, 2],
  });
  assert.equal(unmatched.length, 2);
});
