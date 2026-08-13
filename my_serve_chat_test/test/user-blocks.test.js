import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getUserIdsWhoBlocked,
  recipientIdsForChatEvent,
} from '../utils/userBlocks.js';

test('recipientIdsForChatEvent skips people who blocked the sender', () => {
  const members = [{ user_id: 1 }, { user_id: 2 }, { user_id: 3 }];
  const ids = recipientIdsForChatEvent(members, {
    usersWhoBlockedSender: [2],
  });
  assert.deepEqual(ids, ['1', '3']);
});

test('recipientIdsForChatEvent also honors excludeUserId', () => {
  const members = [{ user_id: '1' }, { user_id: '2' }];
  const ids = recipientIdsForChatEvent(members, {
    excludeUserId: 1,
    usersWhoBlockedSender: [],
  });
  assert.deepEqual(ids, ['2']);
});

test('recipientIdsForChatEvent drops empty member ids', () => {
  const ids = recipientIdsForChatEvent([{ user_id: null }, { user_id: 4 }], {
    usersWhoBlockedSender: [],
  });
  assert.deepEqual(ids, ['4']);
});

test('getUserIdsWhoBlocked returns blockers from pool', async () => {
  const pool = {
    async query(sql, params) {
      assert.match(sql, /user_blocks/);
      assert.deepEqual(params, [42]);
      return { rows: [{ blocker_id: 7 }, { blocker_id: 9 }] };
    },
  };
  const ids = await getUserIdsWhoBlocked(pool, 42);
  assert.deepEqual(ids, [7, 9]);
});

test('getUserIdsWhoBlocked swallows missing-table errors', async () => {
  const pool = {
    async query() {
      throw new Error('relation "user_blocks" does not exist');
    },
  };
  const ids = await getUserIdsWhoBlocked(pool, 1);
  assert.deepEqual(ids, []);
});
