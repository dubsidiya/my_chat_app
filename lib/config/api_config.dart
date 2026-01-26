/// Конфиг API для приложения.
///
/// Можно переопределить URL при сборке через:
/// `--dart-define=API_BASE_URL=https://...`
class ApiConfig {
  static const String _defaultBaseUrl = 'https://my-server-chat.onrender.com';

  /// Базовый URL API без завершающего `/`.
  static String get baseUrl {
    final v = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: _defaultBaseUrl,
    ).trim();

    if (v.isEmpty) return _defaultBaseUrl;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }
}

