import 'dart:js_interop';

@JS('__REOLLITY_BUILD__')
external JSString? get _reollityBuildId;

/// Идентификатор веб-сборки из index.html. Пусто, если страница ещё не проштампована.
String? readWebBuildId() {
  try {
    final value = _reollityBuildId?.toDart.trim() ?? '';
    if (value.isEmpty || value == 'FLUTTER_BUILD_ID') return null;
    return value;
  } catch (_) {
    return null;
  }
}
