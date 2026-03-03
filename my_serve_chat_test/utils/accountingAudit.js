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
    // Важно: если пишем аудит в рамках внешней транзакции (client),
    // любая ошибка вставки переводит транзакцию в aborted state.
    // Чтобы аудит НИКОГДА не ломал бизнес-операцию, используем SAVEPOINT.
    const useSavepoint = Boolean(client && typeof client.query === 'function');
    if (useSavepoint) {
      await db.query('SAVEPOINT audit_event_sp');
    }
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
    if (useSavepoint) {
      await db.query('RELEASE SAVEPOINT audit_event_sp');
    }
  } catch (error) {
    // Если это client-транзакция — откатываемся к SAVEPOINT, чтобы не оставить транзакцию aborted.
    try {
      if (client && typeof client.query === 'function') {
        await db.query('ROLLBACK TO SAVEPOINT audit_event_sp');
        await db.query('RELEASE SAVEPOINT audit_event_sp');
      }
    } catch (_) {
      // ignore
    }
    // Лог аудита не должен ломать бизнес-операции.
    console.warn('Не удалось записать accounting audit event:', error?.message || error);
  }
};
