/// Конфиг API для приложения.
///
/// Можно переопределить URL при сборке через:
/// `--dart-define=API_BASE_URL=https://...`
class ApiConfig {
  static const String _defaultBaseUrl = 'https://reollity.duckdns.org';

  /// Базовый URL API без завершающего `/`.
  static String get baseUrl {
    final v = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: _defaultBaseUrl,
    ).trim();

    if (v.isEmpty) return _defaultBaseUrl;
    return _normalizeBaseUrl(v) ?? _defaultBaseUrl;
  }

  static String? _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.host.isEmpty) return null;
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;

    final portPart = parsed.hasPort && parsed.port > 0 ? ':${parsed.port}' : '';
    final path = parsed.path == '/' ? '' : parsed.path.replaceFirst(RegExp(r'/+$'), '');
    return '${parsed.scheme}://${parsed.host}$portPart$path';
  }
}

