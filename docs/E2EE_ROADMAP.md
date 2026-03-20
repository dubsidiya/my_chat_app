# E2EE Roadmap

This roadmap describes the stabilization and hardening plan for E2EE chat key management.

## Goals

- Eliminate inconsistent decrypt behavior between users.
- Make key delivery resilient to offline users and temporary API failures.
- Support secure key rotation without breaking old messages.
- Reduce retry storms and accidental 429 lockouts.

## Security Invariants (Must Hold)

1. No plaintext fallback in E2EE chats for message send/edit/media paths.
2. Server must never receive private keys in plaintext.
3. Chat key re-share must be authenticated, authorized, and idempotent.
4. Key updates must be monotonic by `key_version` and auditable.
5. Removing a member must prevent access to future key versions.

## Threat Model (Practical Scope)

- Attacker with intercepted network traffic.
- Compromised/stale server rows (old `chat_keys` records).
- Client reinstall/device change with stale local key material.
- Request storms causing 429 during key exchange windows.
- Logic bugs in group membership transitions.

Out of scope for this phase:

- Full key transparency log.
- Post-quantum cryptography migration.

## Phase 1: Data Model and Backward Compatibility

1. Add `chat_key_version` to chat key and message flows.
2. Store keys per `(chat_id, user_id, key_version)` instead of one key per user+chat.
3. Keep backward compatibility:
   - If `key_version` is missing in old records, treat as `1`.
   - Old clients continue to work during migration window.
4. Ensure upsert logic updates stale key records (`ON CONFLICT ... DO UPDATE`).
5. Add explicit DB constraints and indexes:
   - unique `(chat_id, user_id, key_version)`
   - index on `(chat_id, key_version)`
   - index on `(user_id, chat_id)`

## Phase 2: Reliable Key Delivery

1. Introduce server-side pending key requests (`chat_key_requests`).
2. When a user has no key:
   - Create pending request.
   - Notify eligible online members.
   - Keep request until fulfilled (or expired).
3. Add idempotent request handling to avoid duplicate spam.
4. Keep targeted key sharing (`shareChatKeyWithUsers`) as the primary response path.

## Phase 3: Client Key State Machine

For each chat, maintain explicit E2EE state:

- `ready`
- `missing_key`
- `requesting_key`
- `retry_backoff`
- `failed`

Behavior:

1. Request key only when state requires it.
2. Use exponential backoff + jitter.
3. Avoid parallel key request loops for the same chat.
4. Show deterministic UI status based on state, not ad-hoc snackbars.

## Phase 4: Key Rotation

Rotate chat key on high-risk events:

- member removed from chat
- keypair changed for a participant
- manual admin-triggered rotation

Rules:

1. New messages use latest `key_version`.
2. Old messages remain decryptable with historical versions.
3. Re-distribute new key version to active members.
4. Define rotation policy:
   - immediate on member removal
   - deferred (scheduled) on non-critical key refresh
   - manual emergency rotate endpoint for admins

## Phase 5: Rate Limit and Transport Hardening

1. Keep auth-aware rate-limit keys (`IP + token fragment`) for authenticated APIs.
2. Separate limiter budgets for:
   - general API
   - E2EE endpoints
   - uploads
3. Add soft server-side dedup for repeated `request-key` bursts.
4. Ensure mobile/debug environments have sane limits to prevent false 429 during testing.

## Phase 6: Observability and Recovery

1. Add structured server logs/events:
   - `key_request_created`
   - `key_shared`
   - `key_fetch_success`
   - `key_fetch_miss`
   - `key_version_mismatch`
2. Add lightweight client debug telemetry in debug mode.
3. Provide admin recovery action:
   - force reissue key(s) for a chat/user/version.
4. Add operational dashboards/alerts:
   - `key_fetch_miss` spike
   - 429 rate on `/e2ee/*`
   - median key delivery latency (request -> stored -> fetched)

## Phase 7: UX and Product Behavior

1. Define UX for undecryptable states:
   - stable label (`[зашифровано]`)
   - status line (`requesting key`, `retrying`, `needs sender online`)
2. Disable send in strict E2EE mode when key is unavailable.
3. Add manual “Retry key exchange” action in chat menu.
4. Ensure no infinite snackbars or repeated blocking popups.

## Phase 8: Test Plan (Mandatory)

Scenarios:

1. Two users, one offline during key request.
2. Reinstall/reset on one user.
3. Keypair refresh for one user.
4. Add/remove member in group chat.
5. High request pressure (429 simulation).
6. History decryption with mixed key versions.

Acceptance criteria:

- No permanent `[зашифровано]` state after successful key issuance.
- No plaintext fallback in E2EE chat message send path.
- Stable behavior under temporary 429 and reconnect events.
- Rotation does not break historical decrypt.
- Removed members cannot decrypt messages from newer key versions.

## Rollout, Migration, Rollback

1. Rollout strategy:
   - deploy DB migrations first (additive, backward compatible)
   - deploy server with dual-read/write (`v1` + versioned)
   - deploy clients with `key_version` support
   - enable strict mode/rotation flags gradually
2. Feature flags:
   - `E2EE_KEY_VERSIONING_ENABLED`
   - `E2EE_PENDING_REQUESTS_ENABLED`
   - `E2EE_STRICT_SEND_BLOCK_ENABLED`
3. Rollback plan:
   - keep old read path for `key_version = 1`
   - disable strict send block via flag
   - keep migration reversible where possible (or forward-fix script ready)

## Definition of Done

- No plaintext writes in E2EE chats across send/edit/upload.
- New device/reinstall recovers decrypt within bounded time.
- Group add/remove flows pass automated and manual tests.
- 429 does not cause permanent decrypt failure.
- Runbook documented for support and on-call.

## Suggested Implementation Order

1. DB migrations + server compatibility.
2. Message and key APIs with `key_version`.
3. Pending request workflow.
4. Client state machine + backoff/jitter.
5. Rotation triggers and admin tools.
6. Full regression test run and cleanup.
