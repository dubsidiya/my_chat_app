import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:permission_handler/permission_handler.dart';

import 'microphone_permission.dart';

/// Доступ к камере для видеозвонков.
///
/// Важно (iOS): в `ios/Podfile` должен быть `PERMISSION_CAMERA=1`, иначе
/// `permission_handler` не показывает системный диалог. Даже с макросом
/// финальный источник правды — `getUserMedia` (AVFoundation): ранний отказ
/// плагина не должен блокировать звонок до нативного запроса.
class CameraPermission {
  CameraPermission._();

  /// Best-effort: пытается показать системный диалог.
  /// Возвращает [MicrophoneAccess.granted], если можно продолжать к getUserMedia
  /// (в т.ч. когда статус ещё неизвестен / плагин врёт без макроса).
  /// [permanentlyDenied] — только когда уверены, что нужно вести в Настройки.
  static Future<MicrophoneAccess> ensure() async {
    if (kIsWeb) return MicrophoneAccess.granted;

    try {
      var status = await Permission.camera.status;
      if (status.isGranted || status.isLimited) {
        return MicrophoneAccess.granted;
      }

      // Ещё не спрашивали / можно спросить — request().
      if (!status.isPermanentlyDenied) {
        status = await Permission.camera.request();
        if (status.isGranted || status.isLimited) {
          return MicrophoneAccess.granted;
        }
      }

      // iOS: без PERMISSION_CAMERA=1 (или до первого нативного запроса)
      // permanentlyDenied часто ложный. На Android permanentlyDenied надёжнее.
      if (status.isPermanentlyDenied &&
          defaultTargetPlatform == TargetPlatform.android) {
        return MicrophoneAccess.permanentlyDenied;
      }

      // deferred: пусть getUserMedia сам поднимет AVCapture / Camera2 диалог.
      return MicrophoneAccess.granted;
    } catch (e) {
      if (kDebugMode) print('CameraPermission: $e');
      return MicrophoneAccess.granted;
    }
  }

  static Future<bool> openSettings() => MicrophonePermission.openSettings();
}
