void mountWebNativeSend({
  required String apiBase,
  required String chatId,
  required Future<String?> Function() getToken,
  required void Function(String text, Map<String, dynamic>? json) onSent,
  required void Function(String message) onError,
}) {}

void unmountWebNativeSend() {}
