import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'webrtc_web_secure_context.dart';

/// Проверка, можно ли безопасно использовать WebRTC на этом устройстве.
class WebRtcDeviceSupport {
  WebRtcDeviceSupport._();

  static const MethodChannel _channel = MethodChannel('reollity/device');

  /// Браузер разрешает getUserMedia/WebRTC только в secure context (HTTPS / localhost).
  static bool get webCallsAllowed => !kIsWeb || isWebSecureContext();

  static const String insecureWebContextMessage =
      'Голосовые звонки в браузере работают только по HTTPS '
      '(или на localhost при разработке).';

  static bool? _cachedUnsupportedSimulator;

  /// iOS Simulator / Android emulator — нативный WebRTC часто вешает или роняет процесс.
  static Future<bool> isUnsupportedSimulator() async {
    if (kIsWeb) return false;
    final cached = _cachedUnsupportedSimulator;
    if (cached != null) return cached;
    try {
      final v = await _channel.invokeMethod<bool>('isSimulator');
      _cachedUnsupportedSimulator = v == true;
      return _cachedUnsupportedSimulator!;
    } catch (_) {
      _cachedUnsupportedSimulator = false;
      return false;
    }
  }

  static const String unsupportedSimulatorMessage =
      'Голосовые звонки недоступны на симуляторе и Android-эмуляторе. '
      'Используйте приложение на реальном iPhone или Android.';
}
