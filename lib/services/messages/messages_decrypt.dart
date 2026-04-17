import '../../models/message.dart';
import '../e2ee_service.dart';

/// Расшифровка сообщений для отображения (E2EE + вложенный reply).
class MessagesDecrypt {
  static Future<Message> decryptOne(String chatId, Message m) async {
    String content = m.content;
    if (E2eeService.isEncrypted(content)) {
      content = await E2eeService.decryptMessage(chatId, content, keyVersion: m.keyVersion);
      if (content == '[зашифровано]') {
        await E2eeService.requestChatKey(chatId, keyVersion: m.keyVersion);
        final ok = await E2eeService.waitForChatKeyFromServer(chatId, keyVersion: m.keyVersion);
        if (ok) {
          content = await E2eeService.decryptMessage(chatId, m.content, keyVersion: m.keyVersion);
        }
      }
    }
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
      keyVersion: m.keyVersion,
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
