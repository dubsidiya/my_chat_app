import '../../models/message.dart';
import '../chat_key_service.dart';

/// Расшифровка сообщений для отображения (общий ключ чата).
///
/// Новые сообщения шифруются shared-key чата. Сообщения старых (legacy X25519)
/// чатов сервер расшифровать не может — для них показываем нейтральную заглушку.
class MessagesDecrypt {
  static const String legacyUnavailableLabel = 'Сообщение недоступно';

  /// Текст для отображения: расшифровка shared-key, либо заглушка, если это
  /// нечитаемый шифротекст; обычный (незашифрованный) текст возвращается как есть.
  static Future<String> displayText(String chatId, String content) async {
    final decrypted = await ChatKeyService.decryptText(chatId, content);
    if (decrypted != null) return decrypted;
    // null = это зашифрованная строка, которую не получилось расшифровать.
    return legacyUnavailableLabel;
  }

  static Future<Message> decryptOne(String chatId, Message m) async {
    final content = await displayText(chatId, m.content);
    Message? replyTo = m.replyToMessage;
    if (replyTo != null) {
      replyTo = await decryptOne(chatId, replyTo);
    }
    return Message(
      id: m.id,
      chatId: m.chatId,
      userId: m.userId,
      content: content,
      imageUrl: m.imageUrl,
      originalImageUrl: m.originalImageUrl,
      fileUrl: m.fileUrl,
      fileName: m.fileName,
      fileSize: m.fileSize,
      fileMime: m.fileMime,
      messageType: m.messageType,
      senderEmail: m.senderEmail,
      senderAvatarUrl: m.senderAvatarUrl,
      createdAt: m.createdAt,
      deliveredAt: m.deliveredAt,
      editedAt: m.editedAt,
      isRead: m.isRead,
      readAt: m.readAt,
      replyToMessageId: m.replyToMessageId,
      replyToMessage: replyTo,
      isPinned: m.isPinned,
      reactions: m.reactions,
      isForwarded: m.isForwarded,
      originalChatName: m.originalChatName,
    );
  }

  static Future<List<Message>> decryptMessages(String chatId, List<Message> messages) async {
    final result = <Message>[];
    for (final m in messages) {
      result.add(await decryptOne(chatId, m));
    }
    return result;
  }

  /// Расшифровывает одно сообщение (включая replyToMessage) для отображения в UI.
  static Future<Message> decryptMessageForChat(String chatId, Message raw) async =>
      decryptOne(chatId, raw);
}
