import CryptoKit
import Foundation

enum IOSCallKind: String {
  case direct
  case liveKitGroup
  case legacyGroup
}

/// Non-secret metadata accepted from an APNs VoIP push.
///
/// Parsing is intentionally independent from PushKit and CallKit so it can be
/// exercised by RunnerTests without provider credentials or a physical device.
struct IOSCallPayload {
  static let maximumAge: TimeInterval = 120

  let callId: String
  let callUUID: UUID
  let chatId: String
  let callerId: String
  let callerName: String
  let chatName: String
  let kind: IOSCallKind
  let hasVideo: Bool
  let sentAt: Date?
  let expiresAt: Date

  var isGroup: Bool { kind != .direct }

  init?(dictionary: [AnyHashable: Any], now: Date = Date()) {
    func string(_ keys: String...) -> String? {
      for key in keys {
        if let value = dictionary[key] as? String {
          let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
          if !normalized.isEmpty {
            return normalized
          }
        } else if let value = dictionary[key], !(value is NSNull) {
          let normalized = String(describing: value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if !normalized.isEmpty {
            return normalized
          }
        }
      }
      return nil
    }

    guard
      let callId = string("callKitCallId", "callId", "call_id"),
      callId.count <= 128,
      let chatId = string("chatId", "chat_id"),
      chatId.count <= 128
    else {
      return nil
    }

    let type = string("type") ?? "incoming_call"
    let provider = string("provider")?.lowercased()
    let kind: IOSCallKind
    switch type {
    case "incoming_call":
      kind = .direct
    case "incoming_livekit_group_call":
      guard provider == nil || provider == "livekit" else { return nil }
      kind = .liveKitGroup
    case "incoming_group_call":
      kind = provider == "livekit" ? .liveKitGroup : .legacyGroup
    default:
      return nil
    }

    let explicitUUID = string(
      "callKitUuid",
      "callkitUuid",
      "callkit_uuid",
      "callUuid",
      "callUUID",
      "call_uuid"
    ).flatMap(UUID.init(uuidString:))
    let expiresAt =
      Self.parseDate(dictionary["expiresAt"] ?? dictionary["expires_at"])
      ?? now.addingTimeInterval(75)
    guard expiresAt.timeIntervalSince(now) > -2 else {
      return nil
    }

    let sentAt = Self.parseDate(dictionary["sentAt"] ?? dictionary["sent_at"])
    if let sentAt, now.timeIntervalSince(sentAt) > Self.maximumAge {
      return nil
    }

    let media = string("initialMediaType", "mediaType", "media_type")?.lowercased()
    let callerName =
      string("fromLabel", "fromEmail", "callerName", "chatName")
      ?? (kind == .direct ? "Входящий звонок" : "Групповой звонок")

    self.callId = callId
    self.callUUID = explicitUUID ?? Self.deterministicUUID(for: callId)
    self.chatId = chatId
    self.callerId = string("fromUserId", "from_user_id") ?? ""
    self.callerName = String(callerName.prefix(120))
    self.chatName = String((string("chatName", "chat_name") ?? callerName).prefix(120))
    self.kind = kind
    self.hasVideo = media == "video"
    self.sentAt = sentAt
    self.expiresAt = expiresAt
  }

  var eventDictionary: [String: Any] {
    var result: [String: Any] = [
      "type": kind == .direct
        ? "incoming_call"
        : (kind == .liveKitGroup
          ? "incoming_livekit_group_call"
          : "incoming_group_call"),
      "callId": callId,
      "callUuid": callUUID.uuidString.lowercased(),
      "chatId": chatId,
      "fromUserId": callerId,
      "fromLabel": callerName,
      "chatName": chatName,
      "isGroup": isGroup,
      "provider": kind == .liveKitGroup ? "livekit" : (kind == .legacyGroup ? "mesh" : "raw"),
      "mediaType": hasVideo ? "video" : "audio",
      "expiresAt": Self.iso8601.string(from: expiresAt),
    ]
    if let sentAt {
      result["sentAt"] = Self.iso8601.string(from: sentAt)
    }
    return result
  }

  static func deterministicUUID(for value: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
    // RFC 4122 variant with a deterministic, name-based version marker.
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
      )
    )
  }

  private static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let iso8601WithoutFraction: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static func parseDate(_ raw: Any?) -> Date? {
    if let date = raw as? Date {
      return date
    }
    if let number = raw as? NSNumber {
      let value = number.doubleValue
      return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
    }
    guard let text = raw as? String else { return nil }
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let numeric = Double(normalized) {
      return Date(
        timeIntervalSince1970: numeric > 10_000_000_000 ? numeric / 1000 : numeric
      )
    }
    return iso8601.date(from: normalized)
      ?? iso8601WithoutFraction.date(from: normalized)
  }
}
