import Flutter
import Foundation

enum StablePluginRegistrant {
  static func register(with registry: FlutterPluginRegistry) {
    register(registry, pluginKey: "AudioSessionPlugin", classCandidates: ["AudioSessionPlugin", "audio_session.AudioSessionPlugin"])
    register(registry, pluginKey: "FilePickerPlugin", classCandidates: ["FilePickerPlugin", "file_picker.FilePickerPlugin"])
    register(registry, pluginKey: "FLTFirebaseCorePlugin", classCandidates: ["FLTFirebaseCorePlugin", "firebase_core.FLTFirebaseCorePlugin"])
    register(registry, pluginKey: "FLTFirebaseMessagingPlugin", classCandidates: ["FLTFirebaseMessagingPlugin", "firebase_messaging.FLTFirebaseMessagingPlugin"])
    register(registry, pluginKey: "FlutterLocalNotificationsPlugin", classCandidates: ["FlutterLocalNotificationsPlugin", "flutter_local_notifications.FlutterLocalNotificationsPlugin"])
    register(registry, pluginKey: "FlutterSecureStoragePlugin", classCandidates: ["FlutterSecureStoragePlugin", "flutter_secure_storage.FlutterSecureStoragePlugin"])
    register(registry, pluginKey: "JustAudioPlugin", classCandidates: ["JustAudioPlugin", "just_audio.JustAudioPlugin"])
    register(registry, pluginKey: "FPPPackageInfoPlusPlugin", classCandidates: ["FPPPackageInfoPlusPlugin", "package_info_plus.FPPPackageInfoPlusPlugin"])
    register(registry, pluginKey: "PathProviderPlugin", classCandidates: ["PathProviderPlugin", "path_provider_foundation.PathProviderPlugin"])
    register(registry, pluginKey: "RecordIosPlugin", classCandidates: ["RecordIosPlugin", "record_ios.RecordIosPlugin"])
    register(registry, pluginKey: "SharedPreferencesPlugin", classCandidates: ["SharedPreferencesPlugin", "shared_preferences_foundation.SharedPreferencesPlugin"])
    register(registry, pluginKey: "SqflitePlugin", classCandidates: ["SqflitePlugin", "sqflite_darwin.SqflitePlugin"])
    register(registry, pluginKey: "URLLauncherPlugin", classCandidates: ["URLLauncherPlugin", "url_launcher_ios.URLLauncherPlugin"])
  }

  private static func register(_ registry: FlutterPluginRegistry, pluginKey: String, classCandidates: [String]) {
    for name in classCandidates {
      if let cls = NSClassFromString(name) as? FlutterPlugin.Type {
        if let registrar = registry.registrar(forPlugin: pluginKey) {
          cls.register(with: registrar)
        }
        return
      }
    }
  }
}

