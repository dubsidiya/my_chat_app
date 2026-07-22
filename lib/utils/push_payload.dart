import 'package:flutter/foundation.dart' show TargetPlatform;

bool isIncomingCallPushData(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  return type == 'incoming_call' ||
      type == 'incoming_group_call' ||
      type == 'incoming_livekit_group_call';
}

bool isLiveKitGroupCallPushData(Map<String, dynamic> data) =>
    data['type']?.toString() == 'incoming_livekit_group_call' &&
    data['provider']?.toString() == 'livekit' &&
    int.tryParse(data['protocolVersion']?.toString() ?? '') != null &&
    int.parse(data['protocolVersion'].toString()) >= 2;

String incomingCallPushDedupeKey(Map<String, dynamic> data) {
  final type = data['type']?.toString() ?? '';
  final provider =
      data['provider']?.toString().trim() ??
      (type.startsWith('lkcall_') ? 'livekit' : null);
  final callId =
      data['callId']?.toString() ?? data['call_id']?.toString() ?? '';
  return '${provider == null || provider.isEmpty ? 'legacy' : provider}:$callId';
}

bool isCallReconciliationPushData(Map<String, dynamic> data) {
  return data['type']?.toString() == 'call_reconcile';
}

DateTime? parseCallPushExpiry(Map<String, dynamic> data) {
  final raw = data['expiresAt'] ?? data['expires_at'];
  if (raw == null) return null;
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  final asInt = int.tryParse(raw.toString());
  if (asInt != null && !raw.toString().contains('-')) {
    return DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true);
  }
  return DateTime.tryParse(raw.toString())?.toUtc();
}

bool shouldDiscardIncomingCallPush(Map<String, dynamic> data, {DateTime? now}) {
  if (!isIncomingCallPushData(data)) return false;
  final expiresAt = parseCallPushExpiry(data);
  // Payloads from old clients/servers had no expiry. Keep accepting them and
  // let the authoritative call_status round-trip converge the state.
  if (expiresAt == null) return false;
  return !expiresAt.isAfter((now ?? DateTime.now()).toUtc());
}

bool isApplePushPlatform(TargetPlatform platform) {
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

bool shouldShowForegroundLocalNotification({
  required TargetPlatform platform,
  required bool hasRemoteNotification,
}) {
  // Apple already presents a notification payload because foreground
  // presentation options are enabled. A second local notification duplicates
  // the banner and sound.
  return !(isApplePushPlatform(platform) && hasRemoteNotification);
}

class CallNotificationIdentity {
  final int id;
  final String tag;

  const CallNotificationIdentity({required this.id, required this.tag});
}

String _legacyCallTag(String callId) {
  // Stable FNV-1a fallback for old payloads that predate notificationTag.
  var hash = 0x811C9DC5;
  for (final byte in callId.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return 'call_${hash.toRadixString(16).padLeft(8, '0')}';
}

CallNotificationIdentity callNotificationIdentity(Map<String, dynamic> data) {
  final callId =
      data['callId']?.toString() ?? data['call_id']?.toString() ?? 'unknown';
  final parsedId = int.tryParse(data['notificationId']?.toString() ?? '');
  final tag = data['notificationTag']?.toString().trim();
  return CallNotificationIdentity(
    // FCM's Android display path uses id 0 with a call-specific tag.
    id: parsedId == null || parsedId < 0 ? 0 : parsedId,
    tag: tag == null || tag.isEmpty ? _legacyCallTag(callId) : tag,
  );
}

int? callNotificationTimeoutMs(Map<String, dynamic> data, {DateTime? now}) {
  final expiresAt = parseCallPushExpiry(data);
  if (expiresAt == null) return null;
  final remaining = expiresAt
      .difference((now ?? DateTime.now()).toUtc())
      .inMilliseconds;
  return remaining <= 0 ? 1 : remaining;
}
