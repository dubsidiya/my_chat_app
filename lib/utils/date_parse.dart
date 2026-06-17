/// Парсинг дат с API без сдвига календарного дня (PostgreSQL `date`).
DateTime parseCalendarDate(dynamic raw) {
  final p = raw.toString().trim().split('T').first;
  final parts = p.split('-');
  if (parts.length == 3) {
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y != null && m != null && d != null) {
      return DateTime(y, m, d);
    }
  }
  final parsed = DateTime.tryParse(p);
  if (parsed == null) {
    throw FormatException('Invalid calendar date: $raw');
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Мгновение с сервера (ISO UTC). Строки без TZ считаем UTC.
DateTime parseServerInstant(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
  final hasTz = RegExp(r'([zZ]|[+-]\d{2}:?\d{2})$').hasMatch(s);
  if (hasTz) {
    return DateTime.parse(s);
  }
  final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
  final parsed = DateTime.parse(normalized);
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}

DateTime serverInstantToLocal(DateTime instant) =>
    instant.isUtc ? instant.toLocal() : instant;
