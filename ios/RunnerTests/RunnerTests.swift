import CallKit
import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  private final class FakeProvider: IOSCallProviderType {
    weak var delegate: CXProviderDelegate?
    var reported: [(UUID, CXCallUpdate)] = []
    var ended: [(UUID, CXCallEndedReason)] = []

    func setDelegate(
      _ delegate: CXProviderDelegate?,
      queue: DispatchQueue?
    ) {
      self.delegate = delegate
    }

    func reportNewIncomingCall(
      with UUID: UUID,
      update: CXCallUpdate,
      completion: @escaping (Error?) -> Void
    ) {
      reported.append((UUID, update))
      completion(nil)
    }

    func reportCall(
      with UUID: UUID,
      endedAt dateEnded: Date?,
      reason: CXCallEndedReason
    ) {
      ended.append((UUID, reason))
    }

    func reportCall(with UUID: UUID, updated update: CXCallUpdate) {}
  }

  private final class FakeController: IOSCallControllerType {
    var transactions: [CXTransaction] = []

    func request(
      _ transaction: CXTransaction,
      completion: @escaping (Error?) -> Void
    ) {
      transactions.append(transaction)
      completion(nil)
    }
  }

  func testDeterministicFallbackUUIDIsStable() {
    let first = IOSCallPayload.deterministicUUID(for: "call-123")
    let second = IOSCallPayload.deterministicUUID(for: "call-123")
    let other = IOSCallPayload.deterministicUUID(for: "call-456")
    XCTAssertEqual(first, second)
    XCTAssertNotEqual(first, other)
    XCTAssertEqual((first.uuid.6 & 0xF0), 0x50)
  }

  func testParserAcceptsLiveKitMetadataAndRejectsStalePayload() {
    let now = Date()
    let uuid = UUID()
    let payload = IOSCallPayload(
      dictionary: [
        "type": "incoming_livekit_group_call",
        "provider": "livekit",
        "callId": "group-call",
        "callKitUuid": uuid.uuidString,
        "chatId": "42",
        "chatName": "Team",
        "fromUserId": "7",
        "fromLabel": "Caller",
        "mediaType": "video",
        "expiresAt": ISO8601DateFormatter().string(
          from: now.addingTimeInterval(60)
        ),
      ],
      now: now
    )
    XCTAssertEqual(payload?.kind, .liveKitGroup)
    XCTAssertEqual(payload?.callUUID, uuid)
    XCTAssertEqual(payload?.hasVideo, true)

    let stale = IOSCallPayload(
      dictionary: [
        "type": "incoming_call",
        "callId": "stale",
        "chatId": "42",
        "expiresAt": ISO8601DateFormatter().string(
          from: now.addingTimeInterval(-10)
        ),
      ],
      now: now
    )
    XCTAssertNil(stale)
  }

  func testCoordinatorReportsBeforeFlutterAndDrainsQueuedEvent() {
    let suite = "RunnerTests.CallKit.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let provider = FakeProvider()
    let coordinator = IOSCallCoordinator(
      provider: provider,
      callController: FakeController(),
      defaults: defaults
    )
    let completed = expectation(description: "PushKit completion")
    coordinator.receiveIncomingPayloadForTesting(
      [
        "type": "incoming_call",
        "callId": "call-123",
        "callKitUuid": "123e4567-e89b-42d3-a456-426614174000",
        "chatId": "8",
        "fromUserId": "6",
        "fromLabel": "Caller",
        "expiresAt": ISO8601DateFormatter().string(
          from: Date().addingTimeInterval(60)
        ),
      ]
    ) {
      completed.fulfill()
    }
    wait(for: [completed], timeout: 1)

    XCTAssertEqual(provider.reported.count, 1)
    let drained = coordinator.drain()
    XCTAssertEqual((drained["calls"] as? [[String: Any]])?.count, 1)
    let events = drained["events"] as? [[String: Any]]
    XCTAssertEqual(events?.first?["type"] as? String, "incomingReported")
    defaults.removePersistentDomain(forName: suite)
  }

  func testAnswerFromAppRequestsCallKitAnswerWithoutFlutterEvent() {
    let suite = "RunnerTests.CallKit.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let provider = FakeProvider()
    let controller = FakeController()
    let coordinator = IOSCallCoordinator(
      provider: provider,
      callController: controller,
      defaults: defaults
    )
    let callUUID = UUID(uuidString: "123e4567-e89b-42d3-a456-426614174000")!
    let reported = expectation(description: "incoming reported")
    coordinator.receiveIncomingPayloadForTesting(
      [
        "type": "incoming_call",
        "callId": "call-123",
        "callKitUuid": callUUID.uuidString,
        "chatId": "8",
        "fromUserId": "6",
        "fromLabel": "Caller",
        "expiresAt": ISO8601DateFormatter().string(
          from: Date().addingTimeInterval(60)
        ),
      ]
    ) {
      reported.fulfill()
    }
    wait(for: [reported], timeout: 1)
    _ = coordinator.drain()

    var events: [[String: Any]] = []
    coordinator.setEventSink { events.append($0) }

    let answered = expectation(description: "answerFromApp")
    coordinator.answerFromApp(callUUID: callUUID) { ok in
      XCTAssertTrue(ok)
      answered.fulfill()
    }
    wait(for: [answered], timeout: 1)

    XCTAssertEqual(controller.transactions.count, 1)
    let action = controller.transactions[0].actions.first as? CXAnswerCallAction
    XCTAssertEqual(action?.callUUID, callUUID)

    // Simulate CallKit delivering the requested answer action.
    provider.delegate?.provider(
      CXProvider(configuration: CXProviderConfiguration(localizedName: "test")),
      perform: action!
    )
    XCTAssertTrue(events.isEmpty, "in-app answer must not re-enter Flutter")
    defaults.removePersistentDomain(forName: suite)
  }

  func testRingingEndEmitsDeclinedNotLocalEnded() {
    let suite = "RunnerTests.CallKit.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let provider = FakeProvider()
    let coordinator = IOSCallCoordinator(
      provider: provider,
      callController: FakeController(),
      defaults: defaults
    )
    let callUUID = UUID(uuidString: "123e4567-e89b-42d3-a456-426614174000")!
    let reported = expectation(description: "incoming reported")
    coordinator.receiveIncomingPayloadForTesting(
      [
        "type": "incoming_call",
        "callId": "call-123",
        "callKitUuid": callUUID.uuidString,
        "chatId": "8",
        "fromUserId": "6",
        "fromLabel": "Caller",
        "expiresAt": ISO8601DateFormatter().string(
          from: Date().addingTimeInterval(60)
        ),
      ]
    ) {
      reported.fulfill()
    }
    wait(for: [reported], timeout: 1)
    _ = coordinator.drain()

    var events: [[String: Any]] = []
    coordinator.setEventSink { events.append($0) }

    let endAction = CXEndCallAction(call: callUUID)
    provider.delegate?.provider(
      CXProvider(configuration: CXProviderConfiguration(localizedName: "test")),
      perform: endAction
    )

    XCTAssertEqual(events.first?["type"] as? String, "endRequested")
    XCTAssertEqual(events.first?["reason"] as? String, "declined")
    defaults.removePersistentDomain(forName: suite)
  }
}
