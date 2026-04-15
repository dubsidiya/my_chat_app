/**
 * Лог безопасности: фиксация важных событий без PII.
 * В production пишем в console для последующего сбора в SIEM/логах.
 * Формат: JSON одна строка — timestamp, event, ip, userId (опционально).
 */
function getClientIp(req) {
  const ip = req?.ip || req?.get?.('x-forwarded-for')?.split(',')[0]?.trim() || req?.connection?.remoteAddress;
  return ip || 'unknown';
}

const SENSITIVE_KEY_RE = /(token|authorization|cookie|password|secret|private.?key|refresh|session)/i;

function redactValue(key, value) {
  if (value == null) return value;
  if (SENSITIVE_KEY_RE.test(String(key || ''))) return '[REDACTED]';
  if (typeof value === 'string') {
    if (value.length > 512) return `${value.slice(0, 64)}...[TRUNCATED]`;
    return value;
  }
  return value;
}

function sanitizeLogPayload(value, depth = 0) {
  if (depth > 4) return '[TRUNCATED]';
  if (Array.isArray(value)) {
    return value.slice(0, 20).map((item) => sanitizeLogPayload(item, depth + 1));
  }
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      const redacted = redactValue(k, v);
      out[k] = redacted === v ? sanitizeLogPayload(redacted, depth + 1) : redacted;
    }
    return out;
  }
  return value;
}

export function securityEvent(eventType, req, extra = {}) {
  const payload = {
    ts: new Date().toISOString(),
    event: eventType,
    ip: getClientIp(req),
    ...(req?.user?.userId != null && { userId: req.user.userId }),
    ...sanitizeLogPayload(extra),
  };
  if (process.env.NODE_ENV === 'production') {
    console.log('[SECURITY]', JSON.stringify(payload));
  } else {
    console.log('[SECURITY]', payload.event, payload.ip, payload.userId != null ? `userId=${payload.userId}` : '');
  }
}

export function appEvent(eventType, details = {}) {
  const payload = sanitizeLogPayload({
    ts: new Date().toISOString(),
    event: eventType,
    ...details,
  });
  console.log('[APP]', JSON.stringify(payload));
}

export function errorEvent(eventType, err, details = {}) {
  const safeError = {
    message: err?.message || String(err || 'unknown'),
    ...(process.env.NODE_ENV !== 'production' ? { stack: err?.stack || null } : {}),
  };
  const payload = sanitizeLogPayload({
    ts: new Date().toISOString(),
    event: eventType,
    error: safeError,
    ...details,
  });
  console.error('[ERROR]', JSON.stringify(payload));
}
