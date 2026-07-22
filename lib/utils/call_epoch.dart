import 'dart:async';

/// Identifies one call setup generation. A call id alone is insufficient
/// because teardown and a rapid restart can reuse the same asynchronous paths.
class CallEpochToken {
  final String callId;
  final int epoch;

  const CallEpochToken({required this.callId, required this.epoch});
}

/// Small generation guard shared by the DM and group WebRTC implementations.
class CallEpoch {
  int _epoch = 0;
  String? _callId;

  CallEpochToken begin(String callId) {
    _callId = callId;
    _epoch++;
    return CallEpochToken(callId: callId, epoch: _epoch);
  }

  void invalidate() {
    _callId = null;
    _epoch++;
  }

  CallEpochToken? capture() {
    final callId = _callId;
    if (callId == null) return null;
    return CallEpochToken(callId: callId, epoch: _epoch);
  }

  bool isCurrent(CallEpochToken token) {
    return token.epoch == _epoch && token.callId == _callId;
  }
}

/// Adopts a delayed native resource only while [token] is still current.
/// Stale resources are disposed before this future completes.
Future<T?> adoptCallScopedResource<T>({
  required Future<T> resource,
  required CallEpochToken token,
  required bool Function(CallEpochToken token) isCurrent,
  required FutureOr<void> Function(T resource) dispose,
}) async {
  final value = await resource;
  if (isCurrent(token)) return value;
  await dispose(value);
  return null;
}
