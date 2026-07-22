# LiveKit group calls

Group calls are dual-stack:

- raw WebRTC `call_*` remains the only 1:1 transport;
- legacy group mesh remains on `gcall_*`;
- LiveKit group control uses `lkcall_*`; LiveKit carries media;
- a call keeps the transport selected before invitations are sent and never
  changes transport while active.

## Rollout

The safe default is mesh:

```env
GROUP_CALL_DEFAULT_TRANSPORT=mesh
GROUP_CALL_LIVEKIT_ROLLOUT_PERCENT=0
LIVEKIT_GROUP_FEATURE_ENABLED=false
LIVEKIT_DEPLOYMENT_ID=prod
LIVEKIT_GROUP_MAX_PARTICIPANTS=4
LIVEKIT_GROUP_CALL_TTL_MS=14400000
LIVEKIT_TOKEN_TTL_SECONDS=3600
LIVEKIT_ROOM_EMPTY_TIMEOUT_SECONDS=60
LIVEKIT_WEBHOOK_ENABLED=false

LIVEKIT_URL=
LIVEKIT_API_KEY=
LIVEKIT_API_SECRET=
```

Empty credentials are valid while the feature is off. Enabling LiveKit with
the real provider requires all three credentials. `LIVEKIT_GROUP_PROVIDER=fake`
is available only outside production for tests and offline smoke checks.

Selection is deterministic per deployment and chat. Clients without group
protocol version 2 always use mesh. Known old installations in the push-device
registry also keep the chat on mesh, and LiveKit FCM is sent only to devices
advertising protocol version 2. Selection happens on `lkcall_create`;
`lkcall_use_mesh` is a pre-call fallback and does not migrate an active call.

## Security boundary

`POST /calls/group/:callId/token` requires the app JWT, an active invitation
accepted through `lkcall_join`, and current membership in the group chat. Room,
identity, display name and grants are generated on the server. Tokens are
short-lived and responses use `Cache-Control: no-store`.

Participant grants allow room join, microphone, camera and subscriptions only.
They do not include room administration, recording, data publishing or screen
share.

`POST /calls/livekit/webhook` consumes the exact raw
`application/webhook+json` body and verifies the LiveKit signature before
reconciling duplicate-safe participant/room events.

FCM uses `incoming_livekit_group_call` with `provider=livekit` and
`protocolVersion=2`. It includes media type and expiry, but never a LiveKit
token, room name, server URL, API key or secret. `incoming_group_call` remains
the legacy mesh payload.

## Shared state

In production, Redis owns LiveKit sessions, invited/joined participant state,
per-chat and per-user busy leases, expiry, tombstones and webhook dedupe.
Memory mode exists for local tests only; production still requires Redis.

The host starts the room. Explicit host leave ends it for everyone. A provider
disconnect gets the configured reconnect grace before expiry cleanup. Room
creation and deletion are explicit through the server SDK.

## Client behavior

Incoming video calls do not activate camera hardware. The user accepts with
audio or explicitly chooses video. Camera denial falls back to audio. The
Flutter adapter maps participants, publications, active speaker and connection
quality, preserves state during LiveKit reconnect, exposes web autoplay
recovery, and tears down Room/listeners idempotently.

Incoming LiveKit group invites use the same PushKit/CallKit path as 1:1
(`type: incoming_livekit_group_call`, `provider: livekit`) when the callee
has a registered VoIP token. See `docs/PUSH_DEVICES.md` and
`docs/CALLS_ROLLOUT.md` for canary/rollback.
