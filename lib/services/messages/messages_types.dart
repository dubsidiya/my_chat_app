import '../../models/message.dart';

/// Результат пагинации сообщений.
class MessagesPaginationResult {
  final List<Message> messages;
  final bool hasMore;
  final int totalCount;
  final String? oldestMessageId;

  MessagesPaginationResult({
    required this.messages,
    required this.hasMore,
    required this.totalCount,
    this.oldestMessageId,
  });
}

/// Результат загрузки сжатого и опционально оригинального изображения.
class UploadImageUrls {
  final String imageUrl;
  final String? imageStorageKey;
  final String? originalImageUrl;
  final String? originalImageStorageKey;
  const UploadImageUrls({
    required this.imageUrl,
    this.imageStorageKey,
    this.originalImageUrl,
    this.originalImageStorageKey,
  });
}

/// Фрагмент текста только для текста уведомления FCM при E2EE (не хранится в БД как шифротекст).
const int maxPushPreviewChars = 200;

String? pushPreviewPlainForFcm(String originalPlain, String contentSent) {
  final t = originalPlain.trim();
  if (t.isEmpty) return null;
  if (contentSent == originalPlain) return null;
  if (t.length <= maxPushPreviewChars) return t;
  return '${t.substring(0, maxPushPreviewChars)}…';
}

/// Минимальный числовой id в списке (временные `temp_*` и прочие нечисловые id пропускаются).
String? oldestNumericMessageId(List<Message> messages) {
  if (messages.isEmpty) return null;
  int? best;
  for (final m in messages) {
    final n = int.tryParse(m.id);
    if (n != null && (best == null || n < best)) best = n;
  }
  return best?.toString();
}

MessagesPaginationResult buildPaginatedCacheResult(
  List<Message> decrypted, {
  required int limit,
  String? beforeMessageId,
}) {
  final sorted = List<Message>.from(decrypted)
    ..sort((a, b) {
      final ai = int.tryParse(a.id);
      final bi = int.tryParse(b.id);
      if (ai != null && bi != null) return bi.compareTo(ai);
      return b.createdAt.compareTo(a.createdAt);
    });

  List<Message> source = sorted;
  final beforeNum = beforeMessageId == null ? null : int.tryParse(beforeMessageId);
  if (beforeNum != null) {
    source = sorted.where((m) {
      final n = int.tryParse(m.id);
      return n != null && n < beforeNum;
    }).toList();
  }

  final page = source.take(limit).toList();
  final hasMore = source.length > page.length;
  final chronological = page.reversed.toList();
  return MessagesPaginationResult(
    messages: chronological,
    hasMore: hasMore,
    totalCount: decrypted.length,
    oldestMessageId: oldestNumericMessageId(chronological),
  );
}

Map<String, dynamic> searchResultToSnippet(
  Map<String, dynamic> item,
  String plainContent,
  String queryLower,
) {
  String snippet = plainContent;
  if (queryLower.isNotEmpty && plainContent.toLowerCase().contains(queryLower)) {
    final idx = plainContent.toLowerCase().indexOf(queryLower);
    final start = idx > 40 ? idx - 40 : 0;
    final end = (idx + queryLower.length + 40).clamp(0, plainContent.length);
    snippet =
        '${start > 0 ? '…' : ''}${plainContent.substring(start, end)}${end < plainContent.length ? '…' : ''}';
  } else if (plainContent.length > 120) {
    snippet = '${plainContent.substring(0, 120)}…';
  }
  return {
    'message_id': item['message_id'],
    'key_version': item['key_version'] ?? 1,
    'content_snippet': snippet,
    'message_type': item['message_type'],
    'image_url': item['image_url'],
    'created_at': item['created_at'],
    'sender_email': item['sender_email'],
    'is_read': item['is_read'] == true,
  };
}
