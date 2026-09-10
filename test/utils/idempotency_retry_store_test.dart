import 'package:flutter_test/flutter_test.dart';

import 'package:my_chat_app/utils/idempotency_retry_store.dart';

void main() {
  setUp(IdempotencyRetryStore.debugReset);

  test('same fingerprint reuses key until complete', () {
    const scope = 'deposit-create';
    const fp = 'student=1|amount=1000';
    final a = IdempotencyRetryStore.keyFor(scope: scope, fingerprint: fp);
    final b = IdempotencyRetryStore.keyFor(scope: scope, fingerprint: fp);
    expect(b, a);
    IdempotencyRetryStore.complete(scope: scope, fingerprint: fp);
    final c = IdempotencyRetryStore.keyFor(scope: scope, fingerprint: fp);
    expect(c, isNot(a));
  });

  test('different fingerprints get different keys', () {
    final a = IdempotencyRetryStore.keyFor(scope: 'deposit-create', fingerprint: 'a');
    final b = IdempotencyRetryStore.keyFor(scope: 'deposit-create', fingerprint: 'b');
    expect(a, isNot(b));
  });
}
