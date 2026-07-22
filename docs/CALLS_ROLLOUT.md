# Calls rollout, canary and rollback

Source-of-truth links:

| Topic | Doc |
|-------|-----|
| Redis signaling | [REDIS_SIGNALING.md](./REDIS_SIGNALING.md) |
| LiveKit group | [LIVEKIT_GROUP_CALLS.md](./LIVEKIT_GROUP_CALLS.md) |
| Push devices / VoIP | [PUSH_DEVICES.md](./PUSH_DEVICES.md) |
| iOS CallKit | [IOS_CALLKIT.md](./IOS_CALLKIT.md) |
| TURN / coturn | [VOICE_CALLS_COTURN.md](./VOICE_CALLS_COTURN.md) |

## Safe defaults (ship with flags off)

```env
CALL_REGISTRY_MODE=redis          # production
GROUP_CALL_DEFAULT_TRANSPORT=mesh
GROUP_CALL_LIVEKIT_ROLLOUT_PERCENT=0
LIVEKIT_GROUP_FEATURE_ENABLED=false
# APNs / LiveKit / TURN secrets only in the secret store
```

## Server-first rollout order

1. Apply migrations (`add_push_devices.sql`, etc.) with dual-read still on.
2. Deploy backend with Redis registry, LiveKit dual-stack, APNs VoIP provider,
   TURN HMAC — features **off** / 0% / no secrets still OK.
3. Deploy app that speaks protocol v2, push_devices, CallKit, ICE refresh +
   `setConfiguration` before `restartIce`.
4. Internal canary (audio-only): LiveKit credentials +
   `LIVEKIT_GROUP_FEATURE_ENABLED=true`,
   `GROUP_CALL_LIVEKIT_ROLLOUT_PERCENT=5..10` for known chats / internal users.
   Keep video invites off until audio is green.
5. Raise percent → enable group video → production canary → 100%.
6. Keep mesh as automatic fallback for old clients (`lkcall_use_mesh` pre-call).

## Rollback

| Layer | Action | Do **not** |
|-------|--------|------------|
| LiveKit group | `GROUP_CALL_LIVEKIT_ROLLOUT_PERCENT=0` and/or `LIVEKIT_GROUP_FEATURE_ENABLED=false` | Migrate an **active** LiveKit room mid-call to mesh |
| Redis authority | Drain to one process, then `CALL_REGISTRY_MODE=memory` only if unavoidable | Flip Redis→memory while multi-instance traffic is live |
| APNs VoIP | Unset `APNS_*` — invites fall back to FCM for iOS without VoIP | Send cancel/reconcile over VoIP |
| TURN HMAC | Keep `WEBRTC_TURN_SECRET`; static creds only if secret empty | Commit secrets |

New group sessions follow the flag; in-flight calls keep their transport.

## CI / smoke

- CI: Flutter format/analyze/test; backend `smoke:calls:fakes` with
  `TEST_REDIS_URL` + Redis service; `REQUIRE_REDIS_TESTS=1` fails if Redis
  integration is skipped; full `npm test`.
- Local: `npm run smoke:calls:fakes`, `npm run smoke:call:unit`,
  `npm run smoke:call:turn`.
- Live account smokes (`smoke:call:signaling`, `smoke:call:group`) need
  `SMOKE_USER_*` and stay staging-only.
- Staging LiveKit/APNs/TURN use real credentials; unit tests use fakes only.

## Device / NAT matrix (manual)

- Wi‑Fi ↔ LTE, CGNAT
- UDP blocked → TURN TCP / `turns:` TLS
- Long call past credential TTL → ICE restart with refreshed HMAC
- Relay-only probe: client `iceTransportPolicy: 'relay'` (shape covered by
  `smoke:call:turn`)
- Android 14/15: typed FGS, full-screen intent permission
- iOS: CallKit FG/BG/locked/terminated, two devices, mic/camera denial, BT route

## Legacy cleanup gates (do not delete yet)

### Group mesh (`gcall_*`)

Remove only after:

1. LiveKit at 100% for ≥ one stable release window.
2. No mesh invites in production metrics / logs.
3. Client min version that cannot speak mesh-only group protocol.
4. Explicit follow-up PR (this overhaul keeps dual-stack).

Raw 1:1 `call_*` + coturn stay permanently.

### `users.fcm_token`

Keep dual-read until:

1. All active installs register via `push_devices`.
2. Dual-read metrics show negligible legacy token use for ≥ one release.
3. Explicit migration PR drops column + dual-read path.
