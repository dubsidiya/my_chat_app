/// Декодирует имя файла для отображения (percent-encoded → читаемый текст).
/// Исправляет кодировку, когда сервер или клиент передаёт имя в виде %D0%9F%D1%80...
String decodeFileNameForDisplay(String? raw, {String fallback = 'Файл'}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  try {
    if (!raw.contains('%')) return raw;
    final decoded = Uri.decodeComponent(raw);
    return decoded.isEmpty ? fallback : decoded;
  } catch (_) {
    return raw;
  }
}
