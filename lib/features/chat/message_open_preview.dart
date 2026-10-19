import '../../models/message.dart';
import '../../services/chat_key_service.dart';

/// Короткий текст, пока шифротекст ещё не расшифрован.
/// Не является валидным ciphertext, поэтому повторно не уходит в AES.
const String cipherPreviewPlaceholder = '…';

/// Сообщение для немедленного показа: открытый текст как есть,
/// шифротекст заменяется заглушкой без ожидания ключа.
Message messageForImmediateDisplay(Message message) {
  final reply = message.replyToMessage;
  final maskedReply = reply == null ? null : messageForImmediateDisplay(reply);
  final content = ChatKeyService.isEncryptedText(message.content)
      ? cipherPreviewPlaceholder
      : message.content;
  final replyChanged = !identical(maskedReply, reply);
  if (content == message.content && !replyChanged) return message;
  return _retarget(
    message,
    content: content,
    reply: maskedReply,
    setReply: replyChanged,
  );
}

/// Ещё ждёт расшифровки: сам текст или цитата.
bool messageAwaitsPreview(Message message) {
  if (message.content == cipherPreviewPlaceholder ||
      ChatKeyService.isEncryptedText(message.content)) {
    return true;
  }
  final reply = message.replyToMessage;
  if (reply == null) return false;
  return messageAwaitsPreview(reply);
}

/// Подставляет расшифрованные сообщения только туда, где всё ещё заглушка
/// или шифротекст. Уже открытый текст не затирает.
/// `null` — список не изменился.
List<Message>? patchDecryptedPreviews(
  List<Message> current,
  List<Message> decrypted,
) {
  if (decrypted.isEmpty || current.isEmpty) return null;
  final byId = {for (final message in decrypted) message.id: message};
  var changed = false;
  final next = <Message>[];
  for (final message in current) {
    final update = byId[message.id];
    if (update == null || !messageAwaitsPreview(message)) {
      next.add(message);
      continue;
    }
    changed = true;
    next.add(update);
  }
  if (!changed) return null;
  return next;
}

Message _retarget(
  Message source, {
  required String content,
  Message? reply,
  required bool setReply,
}) {
  return Message(
    id: source.id,
    chatId: source.chatId,
    userId: source.userId,
    content: content,
    imageUrl: source.imageUrl,
    originalImageUrl: source.originalImageUrl,
    fileUrl: source.fileUrl,
    fileName: source.fileName,
    fileSize: source.fileSize,
    fileMime: source.fileMime,
    messageType: source.messageType,
    senderEmail: source.senderEmail,
    senderAvatarUrl: source.senderAvatarUrl,
    createdAt: source.createdAt,
    deliveredAt: source.deliveredAt,
    editedAt: source.editedAt,
    isRead: source.isRead,
    readAt: source.readAt,
    replyToMessageId: source.replyToMessageId,
    replyToMessage: setReply ? reply : source.replyToMessage,
    isPinned: source.isPinned,
    reactions: source.reactions,
    isForwarded: source.isForwarded,
    originalChatName: source.originalChatName,
  );
}
