# E2EE Metadata Threat Model

This document clarifies which chat data is encrypted end-to-end and which metadata remains visible to the server.

## Encrypted Content

- Message text payload in `messages.content` (ciphertext JSON blob).
- Media file bytes before upload when E2EE is active (encrypted bytes in object storage).
- Chat symmetric keys shared per member through E2EE key wrapping.
- Private key backup blob (encrypted with user password using PBKDF2 + AES-GCM).

## Non-Encrypted Metadata

- Sender/receiver identifiers needed for routing (`user_id`, `chat_id`).
- Message timestamps, delivery/read status, reactions, pin state.
- Attachment metadata required for UX (`file_name`, `file_size`, `file_mime`).
- Opaque object keys for media references in DB (not public URLs).

## Metadata Hardening Implemented

- Public object URLs were removed from storage persistence.
- Server stores object keys and returns short-lived presigned URLs only.
- Access to media references is constrained by chat membership checks on message fetch endpoints.
- Logs are redacted for secrets (`token`, `authorization`, `password`, `cookie`, private keys).

## Residual Risks

- Traffic timing, message frequency, and social graph relations are still observable by the backend.
- Notification preview text can reveal user-provided plaintext by design for push UX.
- Device compromise still breaks endpoint security regardless of transport hardening.

## Recommended Operations Controls

- Keep presigned URL TTL short (<= 15 minutes).
- Alert on unusual media access and auth refresh patterns.
- Rotate JWT/refresh secrets on incident response events.
- Periodically review metadata fields for minimization opportunities.
