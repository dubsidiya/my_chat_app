import assert from 'node:assert/strict';
import test from 'node:test';

import { teacherVisibleBalance } from '../services/accounting/teacherStudentBalance.js';

const round2 = (n) => Math.round(n * 100) / 100;

test('shared 10k and two teachers spending 10k each: each sees -5k, not 0', () => {
  const unpaidTotal = 10000 + 10000;
  const a = teacherVisibleBalance({
    myTargetedCredit: 0,
    myLessonSpend: 10000,
    sharedCredit: 10000,
    unpaidTotal,
  });
  const b = teacherVisibleBalance({
    myTargetedCredit: 0,
    myLessonSpend: 10000,
    sharedCredit: 10000,
    unpaidTotal,
  });
  assert.equal(round2(a), -5000);
  assert.equal(round2(b), -5000);
  assert.equal(round2(a + b), -10000);
});

test('shared 10k, only A spent 10k: both see 0 leftover, not a duplicate 10k', () => {
  const unpaidTotal = 10000;
  const a = teacherVisibleBalance({
    myTargetedCredit: 0,
    myLessonSpend: 10000,
    sharedCredit: 10000,
    unpaidTotal,
  });
  const b = teacherVisibleBalance({
    myTargetedCredit: 0,
    myLessonSpend: 0,
    sharedCredit: 10000,
    unpaidTotal,
  });
  assert.equal(round2(a), 0);
  assert.equal(round2(b), 0);
});

test('shared leftover is visible to every linked teacher', () => {
  const a = teacherVisibleBalance({
    myTargetedCredit: 0,
    myLessonSpend: 6000,
    sharedCredit: 10000,
    unpaidTotal: 6000,
  });
  const b = teacherVisibleBalance({
    myTargetedCredit: 0,
    myLessonSpend: 0,
    sharedCredit: 10000,
    unpaidTotal: 6000,
  });
  assert.equal(round2(a), 4000);
  assert.equal(round2(b), 4000);
});

test('targeted credit of A is not given to B', () => {
  const unpaidTotal = 5000;
  const a = teacherVisibleBalance({
    myTargetedCredit: 10000,
    myLessonSpend: 3000,
    sharedCredit: 0,
    unpaidTotal,
  });
  const b = teacherVisibleBalance({
    myTargetedCredit: 0,
    myLessonSpend: 5000,
    sharedCredit: 0,
    unpaidTotal,
  });
  assert.equal(round2(a), 7000);
  assert.equal(round2(b), -5000);
});
