import AVFoundation
import CallKit
import Foundation
import PushKit

#if canImport(WebRTC)
import WebRTC
#endif

protocol IOSCallProviderType: AnyObject {
  func setDelegate(_ delegate: CXProviderDelegate?, queue: DispatchQueue?)
  func reportNewIncomingCall(
    with UUID: UUID,
    update: CXCallUpdate,
    completion: @escaping (Error?) -> Void
  )
  func reportCall(with UUID: UUID, endedAt dateEnded: Date?, reason: CXCallEndedReason)
  func reportCall(with UUID: UUID, updated update: CXCallUpdate)
}

extension CXProvider: IOSCallProviderType {}

protocol IOSCallControllerType: AnyObject {
  func request(_ transaction: CXTransaction, completion: @escaping (Error?) -> Void)
}

extension CXCallController: IOSCallControllerType {}

private enum IOSCallLifecycle: String {
  case reported
  case answerRequested
  case connecting
  case connected
}

private final class IOSCallRecord {
  let payload: IOSCallPayload
  var lifecycle: IOSCallLifecycle
  var isMuted: Bool
  var answerAction: CXAnswerCallAction?
  var suppressEndEvent = false
  var suppressMuteEvent = false

  init(
    payload: IOSCallPayload,
    lifecycle: IOSCallLifecycle = .reported,
    isMuted: Bool = false
  ) {
    self.payload = payload
    self.lifecycle = lifecycle
    self.isMuted = isMuted
  }
}

/// Owns PushKit and CallKit independently of Flutter engine readiness.
///
/// All mutable state is confined to the main queue: PushKit, CXProvider and
/// Flutter channel callbacks are registered there.
final class IOSCallCoordinator: NSObject {
  private static let tokenKey = "reollity.callkit.voip-token.v1"
  private static let tokenEnvironmentKey = "reollity.callkit.voip-environment.v1"
  private static let recordsKey = "reollity.callkit.records.v1"
  private static let pendingEventsKey = "reollity.callkit.pending-events.v1"
  private static let maximumPendingEvents = 128

  private let provider: IOSCallProviderType
  private let callController: IOSCallControllerType
  private let defaults: UserDefaults
  private var pushRegistry: PKPushRegistry?
  private var records: [UUID: IOSCallRecord] = [:]
  private var callIdToUUID: [String: UUID] = [:]
  private var pendingEvents: [[String: Any]] = []
  private var eventSink: (([String: Any]) -> Void)?

  init(
    provider: IOSCallProviderType? = nil,
    callController: IOSCallControllerType? = nil,
    defaults: UserDefaults = .standard
  ) {
    self.provider =
      provider
      ?? CXProvider(configuration: IOSCallCoordinator.makeProviderConfiguration())
    self.callController = callController ?? CXCallController()
    self.defaults = defaults
    super.init()
    self.provider.setDelegate(self, queue: .main)
    restorePendingEvents()
    restoreRecords()
  }

  func start() {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in self?.start() }
      return
    }
    guard pushRegistry == nil else { return }
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    pushRegistry = registry
  }

  func setEventSink(_ sink: (([String: Any]) -> Void)?) {
    precondition(Thread.isMainThread)
    eventSink = sink
    guard let sink else { return }
    let queued = pendingEvents
    pendingEvents.removeAll()
    persistPendingEvents()
    queued.forEach(sink)
  }

  func registrationDictionary() -> [String: Any] {
    var result: [String: Any] = [
      "supported": true,
      "environment": currentAPNsEnvironment(),
    ]
    if let token = defaults.string(forKey: Self.tokenKey), !token.isEmpty {
      result["token"] = token
      result["valid"] = true
    } else {
      result["valid"] = false
    }
    return result
  }

  func currentCalls() -> [[String: Any]] {
    removeExpiredRecords()
    return records.values.map(recordDictionary)
  }

  func drain() -> [String: Any] {
    removeExpiredRecords()
    let events = pendingEvents
    pendingEvents.removeAll()
    persistPendingEvents()
    return [
      "calls": records.values.map(recordDictionary),
      "events": events,
      "registration": registrationDictionary(),
    ]
  }

  func receiveIncomingPayloadForTesting(
    _ dictionary: [AnyHashable: Any],
    completion: @escaping () -> Void
  ) {
    receiveIncomingPush(dictionary, completion: completion)
  }

  @discardableResult
  func completeAnswer(callUUID: UUID, success: Bool) -> Bool {
    guard let record = records[callUUID], let action = record.answerAction else {
      return false
    }
    record.answerAction = nil
    if success {
      record.lifecycle = .connecting
      action.fulfill()
      persistRecords()
    } else {
      action.fail()
      provider.reportCall(with: callUUID, endedAt: Date(), reason: .failed)
      emit(type: "callEnded", record: record, extra: ["reason": "answerFailed"])
      removeRecord(callUUID)
    }
    return true
  }

  @discardableResult
  func reportConnected(callUUID: UUID) -> Bool {
    guard let record = records[callUUID] else { return false }
    if record.lifecycle == .connected { return true }
    record.lifecycle = .connected
    if let action = record.answerAction {
      record.answerAction = nil
      action.fulfill()
    }
    provider.reportCall(with: callUUID, updated: callUpdate(for: record.payload))
    emit(type: "connected", record: record)
    persistRecords()
    return true
  }

  func reportEnd(
    callUUID: UUID,
    reason: String,
    completion: @escaping (Bool) -> Void
  ) {
    guard let record = records[callUUID] else {
      completion(true)
      return
    }

    if reason == "localEnded" || reason == "declined" {
      record.suppressEndEvent = true
      let transaction = CXTransaction(action: CXEndCallAction(call: callUUID))
      callController.request(transaction) { [weak self] error in
        DispatchQueue.main.async {
          guard let self else {
            completion(false)
            return
          }
          if error != nil {
            self.provider.reportCall(
              with: callUUID,
              endedAt: Date(),
              reason: .failed
            )
            self.removeRecord(callUUID)
          }
          completion(error == nil)
        }
      }
      return
    }

    provider.reportCall(
      with: callUUID,
      endedAt: Date(),
      reason: callEndedReason(from: reason)
    )
    emit(type: "callEnded", record: record, extra: ["reason": reason])
    removeRecord(callUUID)
    completion(true)
  }

  func syncMute(
    callUUID: UUID,
    muted: Bool,
    completion: @escaping (Bool) -> Void
  ) {
    guard let record = records[callUUID] else {
      completion(false)
      return
    }
    if record.isMuted == muted {
      completion(true)
      return
    }
    record.suppressMuteEvent = true
    let transaction = CXTransaction(
      action: CXSetMutedCallAction(call: callUUID, muted: muted)
    )
    callController.request(transaction) { [weak record] error in
      DispatchQueue.main.async {
        if error != nil {
          record?.suppressMuteEvent = false
        }
        completion(error == nil)
      }
    }
  }

  private static func makeProviderConfiguration() -> CXProviderConfiguration {
    let configuration = CXProviderConfiguration(localizedName: "Reollity")
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.includesCallsInRecents = true
    return configuration
  }

  private func callUpdate(for payload: IOSCallPayload) -> CXCallUpdate {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(
      type: .generic,
      value: payload.callerId.isEmpty ? payload.chatId : payload.callerId
    )
    update.localizedCallerName = payload.isGroup ? payload.chatName : payload.callerName
    update.hasVideo = payload.hasVideo
    update.supportsDTMF = false
    update.supportsGrouping = false
    update.supportsHolding = false
    update.supportsUngrouping = false
    return update
  }

  private func receiveIncomingPush(
    _ dictionary: [AnyHashable: Any],
    completion: @escaping () -> Void
  ) {
    precondition(Thread.isMainThread)
    guard let payload = IOSCallPayload(dictionary: dictionary) else {
      completion()
      return
    }

    if let existingUUID = callIdToUUID[payload.callId],
      let existing = records[existingUUID]
    {
      emit(type: "duplicateIgnored", record: existing)
      completion()
      return
    }
    if let existing = records[payload.callUUID] {
      emit(type: "duplicateIgnored", record: existing)
      completion()
      return
    }

    let record = IOSCallRecord(payload: payload)
    records[payload.callUUID] = record
    callIdToUUID[payload.callId] = payload.callUUID
    persistRecords()

    // Apple requires this report directly in the PushKit callback. Parsing and
    // local persistence above perform no network work.
    provider.reportNewIncomingCall(
      with: payload.callUUID,
      update: callUpdate(for: payload)
    ) { [weak self] error in
      DispatchQueue.main.async {
        guard let self else {
          completion()
          return
        }
        if let error = error as NSError? {
          self.emit(
            type: "incomingReportFailed",
            record: record,
            extra: ["errorDomain": error.domain, "errorCode": error.code]
          )
          self.removeRecord(payload.callUUID)
        } else {
          self.emit(type: "incomingReported", record: record)
        }
        completion()
      }
    }
  }

  private func configureAudioSession(for payload: IOSCallPayload) {
    let session = AVAudioSession.sharedInstance()
    do {
      var options: AVAudioSession.CategoryOptions = [
        .allowBluetooth,
        .allowBluetoothA2DP,
      ]
      if payload.hasVideo {
        options.insert(.defaultToSpeaker)
      }
      try session.setCategory(.playAndRecord, mode: payload.hasVideo ? .videoChat : .voiceChat, options: options)
      // CallKit owns setActive(true/false); never activate the session here.
    } catch {
      emit(
        type: "audioConfigurationFailed",
        record: records[payload.callUUID],
        payload: payload
      )
    }
  }

  private func callEndedReason(from value: String) -> CXCallEndedReason {
    switch value {
    case "remoteEnded", "hangup", "ended":
      return .remoteEnded
    case "unanswered", "expired", "ringingTimeout":
      return .unanswered
    case "answeredElsewhere":
      return .answeredElsewhere
    case "declinedElsewhere":
      return .declinedElsewhere
    default:
      return .failed
    }
  }

  private func emit(
    type: String,
    record: IOSCallRecord?,
    payload explicitPayload: IOSCallPayload? = nil,
    extra: [String: Any] = [:]
  ) {
    guard let payload = explicitPayload ?? record?.payload else { return }
    var event: [String: Any] = [
      "eventId": UUID().uuidString.lowercased(),
      "type": type,
      "occurredAt": ISO8601DateFormatter().string(from: Date()),
      "call": payload.eventDictionary,
    ]
    for (key, value) in extra {
      event[key] = value
    }
    if let eventSink {
      eventSink(event)
      return
    }
    pendingEvents.append(event)
    if pendingEvents.count > Self.maximumPendingEvents {
      pendingEvents.removeFirst(pendingEvents.count - Self.maximumPendingEvents)
    }
    persistPendingEvents()
  }

  private func emitRegistration(type: String, extra: [String: Any]) {
    var event: [String: Any] = [
      "eventId": UUID().uuidString.lowercased(),
      "type": type,
      "occurredAt": ISO8601DateFormatter().string(from: Date()),
    ]
    for (key, value) in extra {
      event[key] = value
    }
    if let eventSink {
      eventSink(event)
    } else {
      pendingEvents.append(event)
      if pendingEvents.count > Self.maximumPendingEvents {
        pendingEvents.removeFirst(pendingEvents.count - Self.maximumPendingEvents)
      }
      persistPendingEvents()
    }
  }

  private func recordDictionary(_ record: IOSCallRecord) -> [String: Any] {
    [
      "call": record.payload.eventDictionary,
      "state": record.lifecycle.rawValue,
      "isMuted": record.isMuted,
    ]
  }

  private func removeRecord(_ uuid: UUID) {
    guard let record = records.removeValue(forKey: uuid) else { return }
    if callIdToUUID[record.payload.callId] == uuid {
      callIdToUUID.removeValue(forKey: record.payload.callId)
    }
    record.answerAction?.fail()
    record.answerAction = nil
    persistRecords()
  }

  private func removeExpiredRecords() {
    let now = Date()
    let expired = records.compactMap { uuid, record in
      record.payload.expiresAt < now && record.lifecycle == .reported ? uuid : nil
    }
    for uuid in expired {
      if let record = records[uuid] {
        provider.reportCall(with: uuid, endedAt: now, reason: .unanswered)
        emit(type: "callEnded", record: record, extra: ["reason": "expired"])
      }
      removeRecord(uuid)
    }
  }

  private func persistRecords() {
    defaults.set(records.values.map(recordDictionary), forKey: Self.recordsKey)
  }

  private func restoreRecords() {
    guard
      let stored = defaults.array(forKey: Self.recordsKey) as? [[String: Any]]
    else {
      return
    }
    let now = Date()
    for item in stored {
      guard
        let call = item["call"] as? [String: Any],
        let payload = IOSCallPayload(dictionary: call, now: now),
        payload.expiresAt > now
      else {
        continue
      }
      let lifecycle =
        (item["state"] as? String).flatMap(IOSCallLifecycle.init(rawValue:))
        ?? .reported
      let record = IOSCallRecord(
        payload: payload,
        lifecycle: lifecycle,
        isMuted: item["isMuted"] as? Bool ?? false
      )
      records[payload.callUUID] = record
      callIdToUUID[payload.callId] = payload.callUUID
    }
    persistRecords()
  }

  private func persistPendingEvents() {
    defaults.set(pendingEvents, forKey: Self.pendingEventsKey)
  }

  private func restorePendingEvents() {
    pendingEvents =
      defaults.array(forKey: Self.pendingEventsKey) as? [[String: Any]]
      ?? []
    if pendingEvents.count > Self.maximumPendingEvents {
      pendingEvents = Array(pendingEvents.suffix(Self.maximumPendingEvents))
    }
  }

  private func currentAPNsEnvironment() -> String {
    if let value = Bundle.main.object(
      forInfoDictionaryKey: "ReollityAPNSEnvironment"
    ) as? String,
      value == "development" || value == "production"
    {
      defaults.set(value, forKey: Self.tokenEnvironmentKey)
      return value
    }
    if let stored = defaults.string(forKey: Self.tokenEnvironmentKey) {
      return stored
    }
    #if DEBUG
    return "development"
    #else
    return "production"
    #endif
  }
}

extension IOSCallCoordinator: PKPushRegistryDelegate {
  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    guard !token.isEmpty else { return }
    let environment = currentAPNsEnvironment()
    defaults.set(token, forKey: Self.tokenKey)
    defaults.set(environment, forKey: Self.tokenEnvironmentKey)
    emitRegistration(
      type: "voipTokenUpdated",
      extra: ["token": token, "environment": environment]
    )
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else { return }
    defaults.removeObject(forKey: Self.tokenKey)
    emitRegistration(
      type: "voipTokenInvalidated",
      extra: ["environment": currentAPNsEnvironment()]
    )
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    receiveIncomingPush(payload.dictionaryPayload, completion: completion)
  }
}

extension IOSCallCoordinator: CXProviderDelegate {
  func providerDidReset(_ provider: CXProvider) {
    for record in records.values {
      record.answerAction?.fail()
      record.answerAction = nil
      emit(type: "providerReset", record: record, extra: ["reason": "providerReset"])
    }
    records.removeAll()
    callIdToUUID.removeAll()
    persistRecords()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let record = records[action.callUUID] else {
      action.fail()
      return
    }
    if record.answerAction != nil || record.lifecycle == .connected {
      action.fail()
      return
    }
    configureAudioSession(for: record.payload)
    record.lifecycle = .answerRequested
    record.answerAction = action
    persistRecords()
    emit(type: "answerRequested", record: record)
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let record = records[action.callUUID] else {
      action.fulfill()
      return
    }
    action.fulfill()
    let suppress = record.suppressEndEvent
    record.suppressEndEvent = false
    if !suppress {
      emit(type: "endRequested", record: record, extra: ["reason": "localEnded"])
    }
    removeRecord(action.callUUID)
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard let record = records[action.callUUID] else {
      action.fail()
      return
    }
    record.isMuted = action.isMuted
    action.fulfill()
    let suppress = record.suppressMuteEvent
    record.suppressMuteEvent = false
    persistRecords()
    if !suppress {
      emit(type: "muteRequested", record: record, extra: ["muted": action.isMuted])
    }
  }

  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    if let answer = action as? CXAnswerCallAction {
      guard let record = records[answer.callUUID] else { return }
      answer.fail()
      record.answerAction = nil
      provider.reportCall(with: answer.callUUID, endedAt: Date(), reason: .unanswered)
      emit(type: "actionTimedOut", record: record, extra: ["action": "answer"])
      removeRecord(answer.callUUID)
      return
    }
    if let end = action as? CXEndCallAction {
      guard let record = records[end.callUUID] else { return }
      end.fail()
      emit(type: "actionTimedOut", record: record, extra: ["action": "end"])
      removeRecord(end.callUUID)
      return
    }
    if let mute = action as? CXSetMutedCallAction {
      guard let record = records[mute.callUUID] else { return }
      mute.fail()
      emit(type: "actionTimedOut", record: record, extra: ["action": "mute"])
    }
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    #if canImport(WebRTC)
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    #endif
    for record in records.values where
      record.lifecycle == .connecting || record.lifecycle == .connected
    {
      emit(type: "audioActivated", record: record)
    }
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    #if canImport(WebRTC)
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    #endif
    for record in records.values {
      emit(type: "audioDeactivated", record: record)
    }
  }
}
