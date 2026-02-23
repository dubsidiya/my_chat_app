/**
 * Лог безопасности: фиксация важных событий без PII.
 * В production пишем в console для последующего сбора в SIEM/логах.
 * Формат: JSON одна строка — timestamp, event, ip, userId (опционально).
 */
function getClientIp(req) {
  const ip = req?.ip || req?.get?.('x-forwarded-for')?.split(',')[0]?.trim() || req?.connection?.remoteAddress;
  return ip || 'unknown';
}

export function securityEvent(eventType, req, extra = {}) {
  const payload = {
    ts: new Date().toISOString(),
    event: eventType,
    ip: getClientIp(req),
    ...(req?.user?.userId != null && { userId: req.user.userId }),
    ...extra,
  };
  if (process.env.NODE_ENV === 'production') {
    console.log('[SECURITY]', JSON.stringify(payload));
  } else {
    console.log('[SECURITY]', payload.event, payload.ip, payload.userId != null ? `userId=${payload.userId}` : '');
  }
}
