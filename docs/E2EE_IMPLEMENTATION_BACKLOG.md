# E2EE Implementation Backlog

This backlog turns `docs/E2EE_ROADMAP.md` into concrete implementation tasks.

## Milestone 1: Versioned Keys (Foundation)

### 1.1 Database migrations

- [ ] Add `key_version` to `chat_keys` (default `1`, not null).
- [ ] Add `current_key_version` to `chats` (default `1`, not null).
- [ ] Add `key_version` to `messages` (default `1`, not null).
- [ ] Backfill existing rows to `1`.
- [ ] Add constraints/indexes:
  - unique `chat_keys(chat_id, user_id, key_version)`
  - index `chat_keys(chat_id, key_version)`
  - index `messages(chat_id, key_version, created_at)`

**Server files**
- `my_serve_chat_test/migrations/*.sql`

### 1.2 Server API compatibility

- [ ] Update `/e2ee/chat-keys` write path to accept/store `keyVersion`.
- [ ] Update `/e2ee/chat-key/:chatId` read path:
  - optional `?keyVersion=...`
  - default to `chats.current_key_version` if omitted.
- [ ] Ensure upsert is `DO UPDATE` (already done, keep with version key).
- [ ] Update message creation to persist `messages.key_version`.

**Server files**
- `my_serve_chat_test/controllers/e2eeController.js`
- `my_serve_chat_test/controllers/messagesController.js`
- `my_serve_chat_test/controllers/chatsController.js`
- `my_serve_chat_test/routes/e2ee.js`

### 1.3 Client compatibility

- [ ] Extend message model with `keyVersion` field.
- [ ] Include `key_version` in send/edit payloads where applicable.
- [ ] Use message `keyVersion` during decrypt.
- [ ] Default missing version to `1`.

**Client files**
- `lib/models/message.dart`
- `lib/services/messages_service.dart`
- `lib/services/e2ee_service.dart`
- `lib/screens/chat_screen.dart`
- `lib/screens/home_screen.dart`

---

## Milestone 2: Reliable Key Delivery

### 2.1 Pending key requests

- [ ] Create `chat_key_requests` table:
  - `chat_id`, `requester_user_id`, `key_version`, `status`, `created_at`, `updated_at`
  - unique active request per `(chat_id, requester_user_id, key_version)`.
- [ ] Add API endpoint to create request (idempotent).
- [ ] Add API endpoint to list pending requests for eligible members.
- [ ] Add endpoint to mark request fulfilled.

**Server files**
- `my_serve_chat_test/migrations/*.sql`
- `my_serve_chat_test/controllers/e2eeController.js`
- `my_serve_chat_test/routes/e2ee.js`

### 2.2 Targeted key share flow

- [ ] Keep `shareChatKeyWithUsers` as primary path.
- [ ] On `e2ee_request_key`, respond only to `requester_user_id`.
- [ ] Add dedup guard for repeated requests.

**Client files**
- `lib/services/e2ee_service.dart`
- `lib/screens/chat_screen.dart`
- `lib/screens/home_screen.dart`

**Server files**
- `my_serve_chat_test/websocket/websocket.js`
- `my_serve_chat_test/controllers/e2eeController.js`

---

## Milestone 3: Client E2EE State Machine

### 3.1 State model

- [ ] Introduce per-chat key state store:
  - `ready`, `missing_key`, `requesting_key`, `retry_backoff`, `failed`.
- [ ] Refactor ad-hoc checks to state transitions.

**Client files**
- `lib/services/e2ee_service.dart`
- `lib/screens/chat_screen.dart`
- `lib/screens/home_screen.dart`

### 3.2 Retry policy

- [ ] Exponential backoff with jitter for key fetch/retry.
- [ ] Cooldown to prevent parallel or duplicate request loops.
- [ ] Stop conditions (max attempts / timeout / user leaves chat).

---

## Milestone 4: Key Rotation

### 4.1 Rotation triggers

- [ ] Rotate key on member removal.
- [ ] Rotate key on manual admin action.
- [ ] Optional deferred rotation on keypair changes.

**Server files**
- `my_serve_chat_test/controllers/chatsController.js`
- `my_serve_chat_test/controllers/e2eeController.js`
- `my_serve_chat_test/routes/e2ee.js`

### 4.2 Rotation mechanics

- [ ] Increment `chats.current_key_version`.
- [ ] Generate and distribute new key for current members.
- [ ] New messages use latest version.
- [ ] Old messages remain decryptable by historical versions.

---

## Milestone 5: Rate Limit and Transport Hardening

### 5.1 Rate-limit tuning

- [ ] Keep auth-aware keying (`IP + token fragment`) for global/api/e2ee.
- [ ] Define distinct budgets for prod and dev.
- [ ] Add temporary bypass knobs for local stress testing.

**Server files**
- `my_serve_chat_test/index.js`

### 5.2 Request dedup and protection

- [ ] Server dedup for repeated `request-key` bursts.
- [ ] Client-side suppression for same chat + requester + version.

---

## Milestone 6: UX and Product Behavior

### 6.1 User-visible states

- [ ] Stable E2EE status row in chat header or message list top.
- [ ] Action button: `Retry key exchange`.
- [ ] Strict mode: disable send while key is unavailable.

**Client files**
- `lib/screens/chat_screen.dart`
- `lib/widgets/chat_input_bar.dart`

### 6.2 Error messaging

- [ ] Replace ambiguous errors with deterministic E2EE state text.
- [ ] Avoid snackbar spam loops.

---

## Milestone 7: Observability and Recovery

### 7.1 Structured logs and metrics

- [ ] Emit events:
  - `key_request_created`
  - `key_shared`
  - `key_fetch_success`
  - `key_fetch_miss`
  - `key_version_mismatch`
- [ ] Add counters and latency metrics.

**Server files**
- `my_serve_chat_test/controllers/e2eeController.js`
- `my_serve_chat_test/websocket/websocket.js`

### 7.2 Admin recovery

- [ ] Add admin endpoint to force reissue key for:
  - chat
  - user
  - version
- [ ] Add safety checks and audit log.

---

## Milestone 8: QA and Rollout

### 8.1 Automated tests

- [ ] Unit tests for key version selection/decrypt.
- [ ] Integration tests for:
  - reinstall path
  - offline requester
  - member removal + rotation
  - 429 recovery.

### 8.2 Rollout plan

- [ ] Deploy additive DB migration first.
- [ ] Deploy server dual-read/write.
- [ ] Deploy client with fallback to `version=1`.
- [ ] Enable flags gradually:
  - `E2EE_KEY_VERSIONING_ENABLED`
  - `E2EE_PENDING_REQUESTS_ENABLED`
  - `E2EE_STRICT_SEND_BLOCK_ENABLED`

### 8.3 Rollback plan

- [ ] Keep old read path for version `1`.
- [ ] Allow disabling strict-send by flag.
- [ ] Prepare forward-fix scripts for partial migrations.

---

## Recommended Execution Order (Practical)

1. Milestone 1 (DB + compatibility).
2. Milestone 2 (pending requests + targeted delivery).
3. Milestone 3 (client state machine + retry discipline).
4. Milestone 5 (rate-limit hardening) in parallel with 2-3.
5. Milestone 4 (rotation) after compatibility is stable.
6. Milestone 6-7 (UX + observability).
7. Milestone 8 (full regression + staged rollout).
