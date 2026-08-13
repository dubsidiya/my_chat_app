/**
 * One-way block: recipient who blocked [sender] must not get their live events.
 * Matches REST: user_blocks.blocker_id = viewer, blocked_id = message.user_id.
 */

export function recipientIdsForChatEvent(
  memberRows,
  { excludeUserId, usersWhoBlockedSender } = {}
) {
  const skip = new Set(
    (usersWhoBlockedSender ?? []).map((id) => id?.toString()).filter(Boolean)
  );
  if (excludeUserId != null && excludeUserId !== '') {
    skip.add(String(excludeUserId));
  }
  return (memberRows ?? [])
    .map((row) => row?.user_id?.toString())
    .filter((id) => id && !skip.has(id));
}

export async function getUserIdsWhoBlocked(pool, senderUserId) {
  if (senderUserId == null || senderUserId === '') return [];
  try {
    const result = await pool.query(
      'SELECT blocker_id FROM user_blocks WHERE blocked_id = $1',
      [senderUserId]
    );
    return result.rows.map((row) => row.blocker_id);
  } catch {
    // Table may be missing on a fresh DB; do not fail message delivery.
    return [];
  }
}
