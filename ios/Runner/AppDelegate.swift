import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Constructed with the app delegate, before Flutter engine/plugin readiness.
  private let iosCallCoordinator = IOSCallCoordinator()
  private var iosCallKitBridge: IOSCallKitBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    iosCallCoordinator.start()
    StablePluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      ReollityDeviceChannel.register(with: controller.binaryMessenger)
      iosCallKitBridge = IOSCallKitBridge(
        coordinator: iosCallCoordinator,
        messenger: controller.binaryMessenger
      )
    }
    return ok
  }
}
