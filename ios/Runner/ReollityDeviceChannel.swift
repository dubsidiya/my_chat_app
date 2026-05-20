import Flutter
import Foundation

enum ReollityDeviceChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "reollity/device",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSimulator":
        #if targetEnvironment(simulator)
        result(true)
        #else
        result(false)
        #endif
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
