import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/call_epoch.dart';

class _FakeNativeResource {
  bool disposed = false;

  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  test('delayed GUM resource is disposed after call epoch changes', () async {
    final epoch = CallEpoch();
    final oldCall = epoch.begin('call-a');
    final delayedGum = Completer<_FakeNativeResource>();

    final adoption = adoptCallScopedResource<_FakeNativeResource>(
      resource: delayedGum.future,
      token: oldCall,
      isCurrent: epoch.isCurrent,
      dispose: (stream) => stream.dispose(),
    );

    epoch.invalidate();
    epoch.begin('call-b');
    final staleStream = _FakeNativeResource();
    delayedGum.complete(staleStream);

    expect(await adoption, isNull);
    expect(staleStream.disposed, isTrue);
  });

  test('delayed peer connection is adopted only in its generation', () async {
    final epoch = CallEpoch();
    final currentCall = epoch.begin('call-a');
    final delayedPeerConnection = Completer<_FakeNativeResource>();

    final adoption = adoptCallScopedResource<_FakeNativeResource>(
      resource: delayedPeerConnection.future,
      token: currentCall,
      isCurrent: epoch.isCurrent,
      dispose: (peerConnection) => peerConnection.dispose(),
    );

    final peerConnection = _FakeNativeResource();
    delayedPeerConnection.complete(peerConnection);

    expect(await adoption, same(peerConnection));
    expect(peerConnection.disposed, isFalse);
  });
}
