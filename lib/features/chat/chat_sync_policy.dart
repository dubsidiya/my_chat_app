class ChatSyncPolicy {
  const ChatSyncPolicy._();

  static bool shouldRunReconnectSync({
    required DateTime now,
    DateTime? lastRunAt,
    Duration minInterval = const Duration(seconds: 10),
  }) {
    if (lastRunAt == null) return true;
    return now.difference(lastRunAt) >= minInterval;
  }
}
