import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:permission_handler/permission_handler.dart';

import 'microphone_permission.dart';

/// Доступ к камере для видеозвонков (тот же permission_handler, что у микрофона).
class CameraPermission {
  CameraPermission._();

  static Future<MicrophoneAccess> ensure() async {
    if (kIsWeb) return MicrophoneAccess.granted;

    try {
      var status = await Permission.camera.status;
      if (status.isGranted || status.isLimited) {
        return MicrophoneAccess.granted;
      }
      if (status.isPermanentlyDenied) {
        return MicrophoneAccess.permanentlyDenied;
      }
      status = await Permission.camera.request();
      if (status.isGranted || status.isLimited) {
        return MicrophoneAccess.granted;
      }
      if (status.isPermanentlyDenied) {
        return MicrophoneAccess.permanentlyDenied;
      }
      return MicrophoneAccess.denied;
    } catch (e) {
      if (kDebugMode) print('CameraPermission: $e');
      // На web/simulator getUserMedia сам покажет отказ; не блокируем заранее.
      return MicrophoneAccess.granted;
    }
  }

  static Future<bool> openSettings() => MicrophonePermission.openSettings();
}
