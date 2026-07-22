# Redis call signaling

Shared authority for 1:1 and group call control-plane state across API
instances. Media still rides raw WebRTC (1:1) or LiveKit (group); Redis only
owns registry, leases, fencing and WS fan-out.

## Modes

| Mode | Env | When |
|------|-----|------|
| `redis` | `CALL_REGISTRY_MODE=redis` (or `REALTIME_MODE=redis`) + `REDIS_URL` | **Required** in production |
| `memory` | `CALL_REGISTRY_MODE=memory` | Local/dev single process only |

There is **no** automatic Redis→memory fallback when Redis is required. A
misconfigured production process fails closed.

## Key env

```env
CALL_REGISTRY_MODE=redis
REDIS_URL=rediss://USER:PASS@HOST:PORT
REDIS_KEY_PREFIX=my-chat          # or REDIS_SIGNALING_NAMESPACE
REDIS_CONNECT_TIMEOUT_MS=5000
REDIS_COMMAND_TIMEOUT_MS=1000

CALL_RINGING_TTL_MS=75000
CALL_ACCEPTED_TTL_MS=90000
CALL_TERMINAL_TTL_MS=300000
CALL_ACCEPTED_DISCONNECT_GRACE_MS=15000
WS_CONNECTION_LEASE_MS=45000
```

See `env-yandex-vm.example.txt` for the full list.

## Code map

| Path | Role |
|------|------|
| `realtime/config.js` | Mode/validation |
| `realtime/redisCallRegistry.js` | Shared call state + Lua-ish scripts |
| `realtime/memoryCallRegistry.js` | Single-process twin |
| `realtime/runtime.js` | Pub/sub delivery + leases |
| `GET /calls/status` | Participant-scoped resume/status for clients |

## Client resume

After WS reconnect the Flutter client uses `call_resume` / `GET /calls/status`
to converge local UI without inventing a new call id.

## Rollback

1. Drain traffic to **one** Node process.
2. Only then flip `CALL_REGISTRY_MODE=memory` if unavoidable.
3. Never flip Redis→memory while multiple instances still accept WS.

Rollout overview: [CALLS_ROLLOUT.md](./CALLS_ROLLOUT.md).
