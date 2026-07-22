-- Normalized per-installation push registry.
-- users.fcm_token intentionally remains for old-client dual-read compatibility.
CREATE TABLE IF NOT EXISTS push_devices (
  installation_id VARCHAR(128) PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform VARCHAR(16) NOT NULL,
  fcm_token TEXT NULL,
  apns_voip_token TEXT NULL,
  apns_environment VARCHAR(16) NULL,
  capabilities JSONB NOT NULL DEFAULT '{}'::jsonb,
  app_version VARCHAR(64) NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  disabled_at TIMESTAMPTZ NULL,
  CONSTRAINT push_devices_installation_id_length
    CHECK (char_length(installation_id) BETWEEN 16 AND 128),
  CONSTRAINT push_devices_platform
    CHECK (platform IN ('android', 'ios', 'web', 'macos', 'windows', 'linux', 'unknown')),
  CONSTRAINT push_devices_apns_environment
    CHECK (apns_environment IS NULL OR apns_environment IN ('development', 'production')),
  CONSTRAINT push_devices_voip_environment_pair
    CHECK (
      (apns_voip_token IS NULL AND apns_environment IS NULL)
      OR
      (apns_voip_token IS NOT NULL AND apns_environment IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_push_devices_user_installation
  ON push_devices(user_id, installation_id);

CREATE INDEX IF NOT EXISTS idx_push_devices_user_active
  ON push_devices(user_id, last_seen_at DESC)
  WHERE disabled_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_push_devices_last_seen
  ON push_devices(last_seen_at);

CREATE UNIQUE INDEX IF NOT EXISTS ux_push_devices_fcm_token
  ON push_devices(fcm_token)
  WHERE fcm_token IS NOT NULL AND fcm_token <> '';

CREATE UNIQUE INDEX IF NOT EXISTS ux_push_devices_apns_voip_token
  ON push_devices(apns_voip_token)
  WHERE apns_voip_token IS NOT NULL AND apns_voip_token <> '';

COMMENT ON TABLE push_devices IS
  'One active push registration per opaque app installation; installation ownership moves atomically on account switch';
COMMENT ON COLUMN push_devices.fcm_token IS
  'Normal Firebase Cloud Messaging token (FCM routes through APNs on iOS)';
COMMENT ON COLUMN push_devices.apns_voip_token IS
  'Native iOS PushKit token used only for incoming VoIP invitations';
COMMENT ON COLUMN push_devices.capabilities IS
  'Client-advertised non-secret push capabilities and payload versions';
