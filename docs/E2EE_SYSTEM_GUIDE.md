# E2EE System Guide

This document is the single technical source of truth for the current E2EE implementation in the project.

It explains:
- what is encrypted and where;
- how keys are generated, shared, stored, and requested;
- how versioned keys (`key_version`) work end-to-end;
- what realtime and fallback flows exist;
- how to diagnose common failures quickly.

---

## 1) Scope and Security Model

### 1.1 What E2EE protects
- Message content (`content`) is encrypted on the client.
- Reply payload text (`reply_to_message.content`) is encrypted/decrypted on the client as part of normal message processing.
- Media/file encryption is handled client-side with chat keys before upload/download paths consume ciphertext.

### 1.2 What server sees
- Server stores ciphertext for E2EE-protected fields.
- Server stores encrypted chat keys per recipient (not plaintext keys).
- Server never needs user private keys.

### 1.3 Trust boundaries
- **Trusted for plaintext:** sender device, recipient device after successful key retrieval/decryption.
- **Untrusted for plaintext:** API server, DB, websocket transport, object storage.

---

## 2) Data Model

## 2.1 Database entities used by E2EE
- `users.public_key`: recipient key-encryption target.
- `users.encrypted_key_backup`: encrypted private key backup for recovery.
- `chats.current_key_version`: active key version for new messages.
- `chat_keys(chat_id, user_id, key_version, encrypted_chat_key)`: per-user encrypted chat key.
- `messages.key_version`: binds each message to the key used for encryption.
- `chat_key_requests(chat_id, requester_user_id, key_version, status)`: pending/fulfilled key delivery state.

### 2.2 Core constraints/indexes
- Unique key slot: `UNIQUE(chat_id, user_id, key_version)` on `chat_keys`.
- Unique request slot: `UNIQUE(chat_id, requester_user_id, key_version)` on `chat_key_requests`.
- Indexes for versioned key lookup and message retrieval by `(chat_id, key_version, created_at)`.

---

## 3) Cryptographic and Client Key Lifecycle

### 3.1 Identity bootstrap
`E2eeService.ensureKeyPair()` guarantees:
- local keypair exists;
- public key is uploaded/synchronized to server (with retry behavior);
- app can participate in key exchange without waiting for user relogin.

### 3.2 Chat key cache format
Local secure storage key naming:
- default: `chatkey_<chatId>`;
- versioned: `chatkey_<chatId>_v<keyVersion>`.

This allows backward-compatible reads and precise version targeting.

### 3.3 Chat key retrieval
`E2eeService.getChatKey(chatId, {keyVersion})`:
- tries local secure cache first using version-aware cache key;
- falls back to server `GET /e2ee/chat-key/:chatId?keyVersion=...`;
- decrypts received encrypted chat key and stores it locally with versioned cache key.

---

## 4) Message Flow (Send/Receive/Display)

### 4.1 Send path
1. Client ensures key pair exists.
2. Client encrypts plaintext with chat key for effective version.
3. Client sends ciphertext payload.
4. Server inserts message with `key_version = chats.current_key_version`.
5. Server includes `key_version` in API response and websocket payload.

If encryption fails due to missing key:
- client triggers `requestChatKey(chatId, keyVersion?)`;
- client waits via `waitForChatKeyFromServer(...)` with adaptive backoff;
- on success retries encryption and send.

### 4.2 Receive path
1. Client receives message (REST or WS) with `key_version`.
2. Client decrypts content using `decryptMessage(chatId, encrypted, keyVersion: message.keyVersion)`.
3. If decryption fails and ciphertext marker remains (`[зашифровано]` path), UI triggers key request/retry state machine.

### 4.3 UI state machine (`chat_screen`)
`_E2eeKeyState`:
- `ready`: key exists, normal send/receive.
- `missing`: no key yet.
- `requesting`: request submitted, waiting.
- `retryBackoff`: polling/retry in progress.
- `failed`: retries exhausted/error state.

UI behavior:
- blocks send when key state is not ready;
- shows explicit status text/snackbars;
- auto-reloads messages when key arrives.

---

## 5) Key Delivery and Reliability

### 5.1 Direct sharing to known users
`shareChatKeyWithUsers(chatId, userIds, {keyVersion})`:
- loads chat key from local secure storage;
- encrypts key for each target user public key;
- stores via server `/e2ee/chat-keys`.

Server `storeChatKeys` uses upsert:
- `ON CONFLICT (chat_id, user_id, key_version) DO UPDATE`
- avoids stale-key deadlocks caused by old `DO NOTHING`.

### 5.2 Request flow for missing key
`requestChatKey(chatId, {keyVersion})`:
- rate-throttled on client by `chatId:keyVersion` tuple;
- server records/upserts `chat_key_requests` as `pending`;
- server emits websocket event `e2ee_request_key` to chat members.

If requester already has key:
- server returns `alreadyHasKey: true`;
- marks request fulfilled without unnecessary broadcast.

### 5.3 Pending request processing
`processPendingKeyRequests(chatId)`:
- owner/member with key fetches pending requests;
- groups by `keyVersion`;
- shares keys in batches to requesters;
- server marks fulfilled on successful store.

This handles offline/late participants and transient WS misses.

---

## 6) Versioning (`key_version`) Contract

`key_version` is required for correctness under rotation and historical reads.

### 6.1 Server obligations
- all message-producing endpoints include `key_version`;
- WS message and message_edited events include `key_version`;
- key endpoints accept/return `keyVersion`.

### 6.2 Client obligations
- message model keeps `keyVersion`;
- decrypt path always prefers message `keyVersion`;
- chat key requests/shares pass version when known;
- optimistic/local updates preserve existing `keyVersion`.

### 6.3 Search and pinned consistency
- Search endpoint returns `key_version`, client decrypts search results with that version.
- Pinned messages include `key_version` in payload.

---

## 7) Rate Limiting and Operational Behavior

### 7.1 Limiter key strategy
Server limiters use auth-aware keying (`IP + token fragment`) to reduce false collisions when multiple users share one IP (common in local/dev tests).

### 7.2 E2EE-specific retry strategy
- Client uses adaptive backoff + jitter for key polling.
- Public key upload retries on recoverable limits.
- Request throttling prevents request storms.

---

## 8) Failure Modes and Fast Diagnosis

### 8.1 Symptom: one user sees `[зашифровано]`, another sees plaintext
Check in order:
1. User has `public_key` on server?
2. `chat_keys` has row for `(chat_id, user_id, key_version)`?
3. Request exists in `chat_key_requests` and status transitions to `fulfilled`?
4. `requestChatKey` and `e2ee_request_key` WS event are emitted/handled?
5. Client decrypt call uses message `keyVersion`?

### 8.2 Symptom: endless waiting for key
- Inspect 429 frequency and limiter config.
- Verify `processPendingKeyRequests` is executed by a member with valid key.
- Confirm sharer has local chat key for requested version.

### 8.3 Symptom: search finds nothing though message exists
- Ensure search response includes `key_version`.
- Ensure client decrypts search result with `keyVersion` before local match filter.

---

## 9) API/Realtime Reference (Current)

### 9.1 E2EE endpoints
- `POST /e2ee/chat-keys` - store encrypted chat keys for recipients (version-aware).
- `POST /e2ee/chat/:chatId/request-key` - request missing key (`keyVersion` optional).
- `GET /e2ee/chat/:chatId/key-requests` - list pending requests.
- `GET /e2ee/chat-key/:chatId?keyVersion=...` - fetch encrypted chat key for user/version.

### 9.2 Message endpoints (E2EE-relevant fields)
- send/get/edit/around/search/forward include `key_version` in message payloads.
- realtime `message` and `message_edited` payloads include `key_version`.

---

## 10) Runbook for New E2EE Changes

When changing any message or key logic:
1. Keep `key_version` in DB query `SELECT`, mapping, response DTO, and WS payload.
2. Preserve `keyVersion` in all client-side `Message(...)` rebuilds/merges.
3. Test two-account scenario:
   - both directions send/receive/decrypt;
   - one user joins/reopens late and still gets key;
   - search decrypts historical encrypted messages.
4. Verify no new lints/errors.
5. Update this guide if flow/contracts changed.

---

## 11) Current Limitations / Next Hardening Steps

- Full key rotation UX and automated re-encryption migration are not yet fully productized.
- Media historical decryption across rotated versions should be validated end-to-end if rotation is enabled.
- Additional observability (metrics/alerts for key request backlog and decrypt failures) can be expanded per roadmap/backlog.

---

## 12) Source Pointers

- Client:
  - `lib/services/e2ee_service.dart`
  - `lib/services/messages_service.dart`
  - `lib/screens/chat_screen.dart`
  - `lib/screens/home_screen.dart`
  - `lib/models/message.dart`
- Server:
  - `my_serve_chat_test/controllers/e2eeController.js`
  - `my_serve_chat_test/controllers/messagesController.js`
  - `my_serve_chat_test/routes/e2ee.js`
  - `my_serve_chat_test/index.js`
- Migrations:
  - `my_serve_chat_test/migrations/add_e2ee_key_versioning.sql`
  - `my_serve_chat_test/migrations/add_e2ee_key_requests.sql`
