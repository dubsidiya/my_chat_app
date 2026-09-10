import assert from 'node:assert/strict';
import test from 'node:test';

import { accountingFootprintBlocksDelete } from '../utils/accountDeletionGuard.js';

const empty = {
  students_created: 0,
  teacher_links: 0,
  lessons_created: 0,
  transactions_created: 0,
  reports_created: 0,
  salary_rows: 0,
};

test('empty footprint does not block account delete', () => {
  assert.equal(accountingFootprintBlocksDelete(empty), false);
  assert.equal(accountingFootprintBlocksDelete(null), false);
});

test('any accounting row blocks account delete', () => {
  for (const key of Object.keys(empty)) {
    assert.equal(
      accountingFootprintBlocksDelete({ ...empty, [key]: 1 }),
      true,
      `${key} should block`
    );
  }
});
