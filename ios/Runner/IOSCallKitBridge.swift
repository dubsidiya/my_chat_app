import Flutter
import Foundation

private final class IOSCallEventStreamHandler: NSObject, FlutterStreamHandler {
  private weak var coordinator: IOSCallCoordinator?

  init(coordinator: IOSCallCoordinator) {
    self.coordinator = coordinator
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    coordinator?.setEventSink { event in
      events(event)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    coordinator?.setEventSink(nil)
    return nil
  }
}

/// Narrow Flutter bridge. The coordinator exists before this bridge and queues
/// every native event until a Flutter engine attaches.
final class IOSCallKitBridge {
  static let methodChannelName = "reollity/ios_callkit"
  static let eventChannelName = "reollity/ios_callkit_events"

  private let coordinator: IOSCallCoordinator
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let streamHandler: IOSCallEventStreamHandler

  init(coordinator: IOSCallCoordinator, messenger: FlutterBinaryMessenger) {
    self.coordinator = coordinator
    methodChannel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: Self.eventChannelName,
      binaryMessenger: messenger
    )
    streamHandler = IOSCallEventStreamHandler(coordinator: coordinator)

    eventChannel.setStreamHandler(streamHandler)
    methodChannel.setMethodCallHandler { [weak coordinator] call, result in
      guard let coordinator else {
        result(
          FlutterError(
            code: "coordinator_unavailable",
            message: "iOS call coordinator is unavailable",
            details: nil
          )
        )
        return
      }
      Self.handle(call, coordinator: coordinator, result: result)
    }
  }

  private static func handle(
    _ call: FlutterMethodCall,
    coordinator: IOSCallCoordinator,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "getRegistration":
      result(coordinator.registrationDictionary())
    case "getCurrentCalls":
      result(coordinator.currentCalls())
    case "drain":
      result(coordinator.drain())
    case "completeAnswer":
      guard
        let arguments = call.arguments as? [String: Any],
        let uuid = parseUUID(arguments),
        let success = arguments["success"] as? Bool
      else {
        result(invalidArguments("completeAnswer"))
        return
      }
      result(coordinator.completeAnswer(callUUID: uuid, success: success))
    case "reportConnected":
      guard
        let arguments = call.arguments as? [String: Any],
        let uuid = parseUUID(arguments)
      else {
        result(invalidArguments("reportConnected"))
        return
      }
      result(coordinator.reportConnected(callUUID: uuid))
    case "reportEnd":
      guard
        let arguments = call.arguments as? [String: Any],
        let uuid = parseUUID(arguments),
        let reason = arguments["reason"] as? String,
        reason.count <= 64
      else {
        result(invalidArguments("reportEnd"))
        return
      }
      coordinator.reportEnd(callUUID: uuid, reason: reason) { accepted in
        result(accepted)
      }
    case "syncMute":
      guard
        let arguments = call.arguments as? [String: Any],
        let uuid = parseUUID(arguments),
        let muted = arguments["muted"] as? Bool
      else {
        result(invalidArguments("syncMute"))
        return
      }
      coordinator.syncMute(callUUID: uuid, muted: muted) { accepted in
        result(accepted)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func parseUUID(_ arguments: [String: Any]) -> UUID? {
    let raw =
      arguments["callUuid"] as? String
      ?? arguments["callUUID"] as? String
      ?? arguments["uuid"] as? String
    return raw.flatMap(UUID.init(uuidString:))
  }

  private static func invalidArguments(_ method: String) -> FlutterError {
    FlutterError(
      code: "invalid_arguments",
      message: "Invalid arguments for \(method)",
      details: nil
    )
  }
}
