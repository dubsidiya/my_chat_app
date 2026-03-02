import pool from '../db.js';

export const logAccountingEvent = async ({
  client = null,
  userId = null,
  eventType,
  entityType = null,
  entityId = null,
  payload = null,
}) => {
  if (!eventType || typeof eventType !== 'string') return;
  const db = client || pool;
  try {
    await db.query(
      `INSERT INTO audit_events (user_id, event_type, entity_type, entity_id, payload)
       VALUES ($1, $2, $3, $4, $5::jsonb)`,
      [
        userId ?? null,
        eventType,
        entityType ?? null,
        entityId != null ? String(entityId) : null,
        JSON.stringify(payload ?? {}),
      ]
    );
  } catch (error) {
    // Лог аудита не должен ломать бизнес-операции.
    console.warn('Не удалось записать accounting audit event:', error?.message || error);
  }
};
