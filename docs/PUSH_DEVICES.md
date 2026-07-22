# Push device registry

Apply `my_serve_chat_test/migrations/add_push_devices.sql` before deploying the
new mobile client. The migration is additive: `users.fcm_token` remains in
place and the server dual-reads it for old clients.

Authenticated clients register the current installation with:

```http
PUT /auth/push-devices/current
Content-Type: application/json

{
  "installationId": "opaque-stable-installation-id",
  "platform": "ios",
  "tokens": {
    "fcm": "normal-fcm-token",
    "apnsVoip": "pushkit-voip-token-hex",
    "apnsEnvironment": "production"
  },
  "capabilities": {
    "normalPush": true,
    "voipPush": true,
    "callPayloadVersion": 2,
    "callReconciliation": true
  },
  "appVersion": "1.0.0+4"
}
```

`user_id` is always derived from the JWT. Re-registering an installation
atomically transfers it during an account switch. Logout uses
`DELETE /auth/push-devices/current` with the same `installationId`; deletion is
owner-scoped and idempotent.

### iOS VoIP (PushKit / CallKit)

- `tokens.apnsVoip` + `tokens.apnsEnvironment` (`development` | `production`)
  are required together when `voipPush` is advertised.
- Incoming invites use APNs VoIP (`apns-push-type=voip`, topic
  `<bundle>.voip`, priority 10, expiration 0). Cancel / answered-elsewhere
  stay on normal FCM/APNs background — never VoIP.
- Installations that register a VoIP token skip duplicate iOS FCM invite
  fanout; Android and legacy iOS without VoIP still receive FCM.
- Server credentials: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_AUTH_KEY_PATH`
  (or `APNS_AUTH_KEY_P8`), optional `APNS_VOIP_BUNDLE_ID` (default
  `com.estellia.reol`). Keys stay in the secret store, not the repo.
- Apple Developer VoIP capability, updated provisioning, and a physical
  iPhone matrix remain external activation steps.
