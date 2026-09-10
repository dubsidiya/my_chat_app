import assert from 'node:assert/strict';
import test from 'node:test';

import { asCsv, escapeCsvCell, neutralizeCsvFormula } from '../utils/csvEscape.js';

test('formula injection is prefixed so Excel does not execute it', () => {
  assert.equal(neutralizeCsvFormula(`=cmd|'/c calc'!A1`), `'=cmd|'/c calc'!A1`);
  assert.equal(neutralizeCsvFormula('=HYPERLINK("http://evil","x")'), `'=HYPERLINK("http://evil","x")`);
  assert.equal(neutralizeCsvFormula('+1+1'), `'+1+1`);
  assert.equal(neutralizeCsvFormula('@SUM(A1)'), `'@SUM(A1)`);
  assert.equal(neutralizeCsvFormula('- комиссия'), `'- комиссия`);
  assert.equal(neutralizeCsvFormula(' =1+1'), `' =1+1`);
});

test('plain numbers and ordinary names stay untouched', () => {
  assert.equal(neutralizeCsvFormula('Иванов'), 'Иванов');
  assert.equal(neutralizeCsvFormula('-1500'), '-1500');
  assert.equal(neutralizeCsvFormula('-1500.50'), '-1500.50');
  assert.equal(escapeCsvCell(-1500), '-1500');
  assert.equal(escapeCsvCell(null), '');
});

test('RFC 4180 quoting still works after formula prefix', () => {
  assert.equal(escapeCsvCell('a,b'), '"a,b"');
  assert.equal(escapeCsvCell('say "hi"'), '"say ""hi"""');
  const csv = asCsv([
    ['ученик', 'описание'],
    [`=cmd|'/c calc'!A1`, '- комиссия банка'],
  ]);
  assert.match(csv, /(^|\n)'=cmd\|'\/c calc'!A1,/);
  assert.match(csv, /,'- комиссия банка($|\n)/);
  assert.doesNotMatch(csv, /(^|\n)=cmd/);
});
