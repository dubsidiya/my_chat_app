import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// Android 14+ full-screen incoming-call intent gate.
class AndroidFullScreenIntent {
  AndroidFullScreenIntent._();

  static const MethodChannel _channel = MethodChannel('reollity/device');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> canUseFullScreenIntent() async {
    if (!isSupported) return true;
    try {
      final value = await _channel.invokeMethod<bool>('canUseFullScreenIntent');
      return value ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Returns whether full-screen call UI is allowed. Optionally opens system
  /// settings when denied (Android 14+). Call notifications still show as a
  /// heads-up fallback when this is false.
  static Future<bool> ensureReady({bool openSettingsIfNeeded = false}) async {
    if (await canUseFullScreenIntent()) return true;
    if (openSettingsIfNeeded) await openSettings();
    return canUseFullScreenIntent();
  }

  static Future<void> openSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openFullScreenIntentSettings');
    } catch (_) {}
  }
}
