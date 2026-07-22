import 'dart:async';

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        visibleForTesting;
import 'package:flutter/services.dart';

enum CallKeepAliveOperation {
  unsupported,
  unchanged,
  started,
  updated,
  stopped,
  failed,
}

class CallKeepAliveResult {
  final bool success;
  final bool isRunning;
  final bool isVideo;
  final int attempts;
  final CallKeepAliveOperation operation;
  final Object? error;

  const CallKeepAliveResult({
    required this.success,
    required this.isRunning,
    required this.isVideo,
    required this.attempts,
    required this.operation,
    this.error,
  });
}

typedef CallKeepAliveInvoker =
    Future<Object?> Function(String method, Map<String, dynamic>? arguments);

/// Держит звонок живым в фоне: iOS — через UIBackgroundModes audio (plist);
/// Android — foreground service с типом microphone[/camera].
///
/// Owner leases + serial queue: DM/group не гасят FGS друг у друга, а
/// повторный acquire одного owner остаётся идемпотентным.
class CallKeepAlive {
  CallKeepAlive._();

  static const _channel = MethodChannel('reollity/call_keep_alive');
  static const _legacyOwner = 'legacy-call';
  static final Map<String, bool> _leases = {};
  static bool _started = false;
  static bool _lastIsVideo = false;
  static Future<void> _chain = Future<void>.value();
  static bool? _supportedOverride;
  static List<Duration> _retryDelays = const [
    Duration.zero,
    Duration(milliseconds: 150),
    Duration(milliseconds: 400),
  ];
  static CallKeepAliveInvoker _invoker = _invokePlatform;

  static bool get _isSupported =>
      _supportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static Future<CallKeepAliveResult> acquire({
    required String owner,
    required bool isVideo,
  }) {
    return _enqueue(() {
      _leases[_validatedOwner(owner)] = isVideo;
      return _syncNativeState();
    });
  }

  static Future<CallKeepAliveResult> update({
    required String owner,
    required bool isVideo,
  }) {
    return _enqueue(() {
      _leases[_validatedOwner(owner)] = isVideo;
      return _syncNativeState();
    });
  }

  static Future<CallKeepAliveResult> release({required String owner}) {
    return _enqueue(() {
      _leases.remove(_validatedOwner(owner));
      return _syncNativeState();
    });
  }

  static Future<CallKeepAliveResult> _syncNativeState() async {
    final wantVideo = _leases.values.any((isVideo) => isVideo);
    if (!_isSupported) {
      return const CallKeepAliveResult(
        success: true,
        isRunning: false,
        isVideo: false,
        attempts: 0,
        operation: CallKeepAliveOperation.unsupported,
      );
    }

    if (_leases.isEmpty) {
      if (!_started) {
        return const CallKeepAliveResult(
          success: true,
          isRunning: false,
          isVideo: false,
          attempts: 0,
          operation: CallKeepAliveOperation.unchanged,
        );
      }
      final invocation = await _invokeWithRetry('stop', null);
      if (!invocation.success) {
        return _failedResult(invocation);
      }
      _started = false;
      _lastIsVideo = false;
      return CallKeepAliveResult(
        success: true,
        isRunning: false,
        isVideo: false,
        attempts: invocation.attempts,
        operation: CallKeepAliveOperation.stopped,
      );
    }

    if (_started && _lastIsVideo == wantVideo) {
      return CallKeepAliveResult(
        success: true,
        isRunning: true,
        isVideo: wantVideo,
        attempts: 0,
        operation: CallKeepAliveOperation.unchanged,
      );
    }

    final wasStarted = _started;
    final invocation = await _invokeWithRetry('start', {'isVideo': wantVideo});
    if (!invocation.success) {
      return _failedResult(invocation);
    }
    _started = true;
    _lastIsVideo = wantVideo;
    return CallKeepAliveResult(
      success: true,
      isRunning: true,
      isVideo: wantVideo,
      attempts: invocation.attempts,
      operation: wasStarted
          ? CallKeepAliveOperation.updated
          : CallKeepAliveOperation.started,
    );
  }

  static Future<_NativeInvocation> _invokeWithRetry(
    String method,
    Map<String, dynamic>? arguments,
  ) async {
    Object? lastError;
    for (var i = 0; i < _retryDelays.length; i++) {
      final delay = _retryDelays[i];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      try {
        final value = await _invoker(method, arguments);
        if (_nativeSucceeded(value)) {
          return _NativeInvocation(success: true, attempts: i + 1);
        }
        lastError = StateError('$method returned failure');
      } catch (e) {
        lastError = e;
      }
    }
    if (kDebugMode) {
      print('CallKeepAlive.$method failed: $lastError');
    }
    return _NativeInvocation(
      success: false,
      attempts: _retryDelays.length,
      error: lastError,
    );
  }

  static bool _nativeSucceeded(Object? value) {
    if (value == null) {
      return true; // Backward-compatible native implementation.
    }
    if (value is bool) return value;
    if (value is Map) return value['success'] == true;
    return false;
  }

  static CallKeepAliveResult _failedResult(_NativeInvocation invocation) {
    return CallKeepAliveResult(
      success: false,
      isRunning: _started,
      isVideo: _started && _lastIsVideo,
      attempts: invocation.attempts,
      operation: CallKeepAliveOperation.failed,
      error: invocation.error,
    );
  }

  static Future<Object?> _invokePlatform(
    String method,
    Map<String, dynamic>? arguments,
  ) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }

  static String _validatedOwner(String owner) {
    final value = owner.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(owner, 'owner', 'must not be empty');
    }
    return value;
  }

  static Future<CallKeepAliveResult> _enqueue(
    Future<CallKeepAliveResult> Function() operation,
  ) {
    final completer = Completer<CallKeepAliveResult>();
    _chain = _chain.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// @deprecated use [acquire]/[release]
  static Future<CallKeepAliveResult> start({required bool isVideo}) =>
      acquire(owner: _legacyOwner, isVideo: isVideo);

  /// @deprecated use [release]
  static Future<CallKeepAliveResult> stop() => release(owner: _legacyOwner);

  @visibleForTesting
  static Future<void> debugReset({
    CallKeepAliveInvoker? invoker,
    bool? supported,
    List<Duration>? retryDelays,
  }) async {
    await _chain.catchError((_) {});
    _leases.clear();
    _started = false;
    _lastIsVideo = false;
    _chain = Future<void>.value();
    _invoker = invoker ?? _invokePlatform;
    _supportedOverride = supported;
    _retryDelays =
        retryDelays ??
        const [
          Duration.zero,
          Duration(milliseconds: 150),
          Duration(milliseconds: 400),
        ];
  }
}

class _NativeInvocation {
  final bool success;
  final int attempts;
  final Object? error;

  const _NativeInvocation({
    required this.success,
    required this.attempts,
    this.error,
  });
}
