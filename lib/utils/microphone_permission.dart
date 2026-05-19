import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Результат запроса доступа к микрофону (голосовые сообщения + WebRTC-звонки).
enum MicrophoneAccess {
  granted,
  denied,
  permanentlyDenied,
}

/// Единая проверка/запрос микрофона: сначала через [AudioRecorder] (как в чате),
/// затем через [permission_handler] для повторного запроса и «в Настройки».
class MicrophonePermission {
  MicrophonePermission._();

  static Future<MicrophoneAccess> ensure() async {
    if (kIsWeb) return MicrophoneAccess.granted;

    // Сначала permission_handler — тот же RECORD_AUDIO, что у WebRTC getUserMedia.
    var status = await Permission.microphone.status;
    if (status.isGranted || status.isLimited) {
      return MicrophoneAccess.granted;
    }
    if (status.isPermanentlyDenied) {
      return MicrophoneAccess.permanentlyDenied;
    }
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (status.isGranted || status.isLimited) {
        return MicrophoneAccess.granted;
      }
      if (status.isPermanentlyDenied) {
        return MicrophoneAccess.permanentlyDenied;
      }
    }

    // Fallback: record (как у голосовых сообщений в чате).
    try {
      final recorder = AudioRecorder();
      if (await recorder.hasPermission()) {
        await recorder.dispose();
        return MicrophoneAccess.granted;
      }
      await recorder.dispose();
    } catch (e) {
      if (kDebugMode) print('MicrophonePermission record: $e');
    }

    return MicrophoneAccess.denied;
  }

  static Future<bool> openSettings() => openAppSettings();
}
