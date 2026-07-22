# iOS PushKit / CallKit

Phone-grade incoming calls for Reollity on iOS. Raw WebRTC (1:1) and LiveKit
group flows share one native coordinator; Flutter owns media and signaling
after CallKit answer.

## Native ownership

| Component | Role |
|-----------|------|
| `IOSCallCoordinator` | PushKit registry at launch, CallKit report **before** Flutter/network, pending event queue, UUID map |
| `IOSCallKitBridge` | Method/EventChannel `reollity/ios_callkit` + `_events` |
| `IOSCallPayload` | Non-secret invite metadata parser (no tokens/credentials) |
| `IOSCallKitService` | Dart: drain cold-start, status reconcile, answer/end/mute sync |

CallKit owns the incoming UI while ringing. `VoiceCallHost` skips auto-opening
the Flutter incoming route when `ownsIncomingUI(callId)` is true.

## Answer path

1. User answers in CallKit → native emits `answerRequested`.
2. Flutter connects WS, `GET /calls/status?call_id=…`.
3. If still ringing for this device → `acceptIncomingFromSystem` (DM or group).
4. Native `completeAnswer(success)` fulfills/fails the CXAnswer action.
5. On media connected → `reportConnected`; mute/end stay bidirectional.

First device wins via the Redis/memory call registry; losers get
`answeredElsewhere` (FCM reconcile + CallKit end reason).

## Server

- Invite: APNs VoIP via `services/push/apnsVoipProvider.js`.
- Reconcile/cancel: normal FCM/APNs only (never VoIP).
- Env template: `APNS_*` in `env-yandex-vm.example.txt`.

## External prerequisites

- Apple VoIP capability + provisioning with Push Notifications + Voice over IP.
- APNs Auth Key (`.p8`) in the deployment secret store.
- Physical device matrix: FG/BG/locked/terminated, cancel, stale invite,
  two devices, mic/camera denial, Bluetooth audio route.
