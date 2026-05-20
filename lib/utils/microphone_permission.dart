import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Результат запроса доступа к микрофону (голосовые сообщения + WebRTC-звонки).
enum MicrophoneAccess {
  granted,
  denied,
  permanentlyDenied,
}

/// Единая проверка/запрос микрофона: сначала через [permission_handler]
/// (тот же RECORD_AUDIO, что у WebRTC getUserMedia), при сбоях плагина —
/// fallback через [AudioRecorder] (как у голосовых сообщений), который ходит
/// напрямую в AVAudioSession/MediaRecorder и не зависит от
/// `flutter.baseflow.com/permissions/methods`.
class MicrophonePermission {
  MicrophonePermission._();

  static Future<MicrophoneAccess> ensure() async {
    if (kIsWeb) return MicrophoneAccess.granted;

    // 1) permission_handler. Может бросить MissingPluginException, если
    // нативный pod не зарегистрирован (типичный iOS release/TestFlight баг
    // после `flutter pub get` без `pod install`). Любое исключение здесь
    // НЕ должно ронять весь звонок — переходим к fallback.
    final viaHandler = await _ensureViaPermissionHandler();
    if (viaHandler == MicrophoneAccess.granted) return MicrophoneAccess.granted;
    if (viaHandler == MicrophoneAccess.permanentlyDenied) {
      return MicrophoneAccess.permanentlyDenied;
    }

    // 2) record. Используем при denied и при сбое плагина (viaHandler == null).
    // record на iOS сам триггерит системный диалог через AVAudioSession и
    // не зависит от flutter.baseflow.com/permissions/methods.
    try {
      final recorder = AudioRecorder();
      try {
        if (await recorder.hasPermission()) {
          return MicrophoneAccess.granted;
        }
      } finally {
        try {
          await recorder.dispose();
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) print('MicrophonePermission record fallback: $e');
    }

    return MicrophoneAccess.denied;
  }

  /// Возвращает `null`, если плагин permission_handler недоступен —
  /// тогда вызывающий уйдёт на fallback.
  static Future<MicrophoneAccess?> _ensureViaPermissionHandler() async {
    try {
      var status = await Permission.microphone.status;
      if (status.isGranted || status.isLimited) {
        return MicrophoneAccess.granted;
      }
      if (status.isPermanentlyDenied) {
        return MicrophoneAccess.permanentlyDenied;
      }
      status = await Permission.microphone.request();
      if (status.isGranted || status.isLimited) {
        return MicrophoneAccess.granted;
      }
      if (status.isPermanentlyDenied) {
        return MicrophoneAccess.permanentlyDenied;
      }
      // .denied после request обычно означает «пользователь нажал Don't allow»;
      // повторного диалога iOS не покажет — отдаём denied как финальный ответ,
      // чтобы UI мог предложить «открыть Настройки».
      return MicrophoneAccess.denied;
    } catch (e) {
      if (kDebugMode) {
        print('MicrophonePermission permission_handler unavailable: $e');
      }
      return null;
    }
  }

  static Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (e) {
      if (kDebugMode) print('MicrophonePermission openSettings: $e');
      return false;
    }
  }
}
