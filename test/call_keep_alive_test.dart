import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/call_keep_alive.dart';

void main() {
  tearDown(() async {
    await CallKeepAlive.debugReset();
  });

  test('retries a transient native channel failure', () async {
    var attempts = 0;
    await CallKeepAlive.debugReset(
      supported: true,
      retryDelays: const [Duration.zero, Duration.zero],
      invoker: (method, arguments) async {
        attempts++;
        if (attempts == 1) {
          throw PlatformException(code: 'temporarily_unavailable');
        }
        return true;
      },
    );

    final result = await CallKeepAlive.acquire(owner: 'dm', isVideo: false);

    expect(result.success, isTrue);
    expect(result.attempts, 2);
    expect(result.operation, CallKeepAliveOperation.started);
  });

  test('owner leases preserve DM and group coexistence', () async {
    final calls = <String>[];
    await CallKeepAlive.debugReset(
      supported: true,
      retryDelays: const [Duration.zero],
      invoker: (method, arguments) async {
        calls.add(method);
        return true;
      },
    );

    await CallKeepAlive.acquire(owner: 'dm', isVideo: false);
    await CallKeepAlive.acquire(owner: 'group', isVideo: false);
    await CallKeepAlive.release(owner: 'dm');

    expect(calls, ['start']);

    final result = await CallKeepAlive.release(owner: 'group');
    expect(result.operation, CallKeepAliveOperation.stopped);
    expect(calls, ['start', 'stop']);
  });

  test('video update is sent only after owner upgrades its lease', () async {
    final videoArguments = <bool>[];
    await CallKeepAlive.debugReset(
      supported: true,
      retryDelays: const [Duration.zero],
      invoker: (method, arguments) async {
        if (method == 'start') {
          videoArguments.add(arguments?['isVideo'] == true);
        }
        return true;
      },
    );

    await CallKeepAlive.acquire(owner: 'dm', isVideo: false);
    final result = await CallKeepAlive.update(owner: 'dm', isVideo: true);

    expect(result.success, isTrue);
    expect(result.operation, CallKeepAliveOperation.updated);
    expect(videoArguments, [false, true]);
  });

  test('surfaces native start failure after bounded retries', () async {
    await CallKeepAlive.debugReset(
      supported: true,
      retryDelays: const [Duration.zero, Duration.zero],
      invoker: (method, arguments) async => false,
    );

    final result = await CallKeepAlive.acquire(owner: 'dm', isVideo: false);

    expect(result.success, isFalse);
    expect(result.operation, CallKeepAliveOperation.failed);
    expect(result.attempts, 2);
    expect(result.isRunning, isFalse);
  });
}
