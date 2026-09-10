import 'dart:math';

/// Ключ идемпотентности на логическую операцию, а не на каждый HTTP-вызов.
///
/// Пока запрос не завершился успехом (таймаут, повтор кнопки), тот же
/// [fingerprint] получает тот же ключ — сервер отвечает replay, а не вторым депозитом.
/// После успеха ключ забывается, чтобы следующее такое же пополнение было новой операцией.
class IdempotencyRetryStore {
  IdempotencyRetryStore._();

  static final Random _rnd = Random();
  static const int _randomMax = 1000000000;
  static final Map<String, String> _keys = {};

  static String mint(String scope) {
    final t = DateTime.now().microsecondsSinceEpoch;
    final r = _rnd.nextInt(_randomMax);
    return '$scope-$t-$r';
  }

  static String _id(String scope, String fingerprint) => '$scope|$fingerprint';

  static String keyFor({required String scope, required String fingerprint}) {
    final id = _id(scope, fingerprint);
    return _keys.putIfAbsent(id, () => mint(scope));
  }

  static void complete({required String scope, required String fingerprint}) {
    _keys.remove(_id(scope, fingerprint));
  }

  /// Только для тестов.
  static void debugReset() => _keys.clear();
}
