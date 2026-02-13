import 'package:flutter/services.dart';
import 'storage_service.dart';

/// Сервис для воспроизведения звука и вибрации при новом сообщении.
/// Звук: SystemSound.alert (работает на десктопе; на мобильных может игнорироваться).
/// Вибрация: HapticFeedback (работает на поддерживаемых устройствах).
class NotificationFeedbackService {
  static Future<void> onNewMessage() async {
    final soundEnabled = await StorageService.getSoundOnNewMessage();
    final vibrationEnabled = await StorageService.getVibrationOnNewMessage();

    if (soundEnabled) {
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }

    if (vibrationEnabled) {
      HapticFeedback.heavyImpact();
    }
  }
}
