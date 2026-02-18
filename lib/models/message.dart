import 'package:flutter/foundation.dart' show kDebugMode;

class Message {
  final String id;
  final String chatId;
  final String userId;
  final String content;
  final String? imageUrl;
  final String? originalImageUrl; // ✅ URL оригинального изображения
  final String? fileUrl; // ✅ URL файла-вложения
  final String? fileName; // ✅ Имя файла (оригинальное)
  final int? fileSize; // ✅ Размер файла (bytes)
  final String? fileMime; // ✅ MIME-тип файла
  final String messageType; // 'text', 'image', 'text_image'
  final String senderEmail;
  final String createdAt;
  final String? deliveredAt; // ✅ Время доставки
  final String? editedAt; // ✅ Время редактирования
  final bool isRead; // ✅ Прочитано ли сообщение текущим пользователем
  final String? readAt; // ✅ Время прочтения
  final String? replyToMessageId; // ✅ ID сообщения, на которое отвечают
  final Message? replyToMessage; // ✅ Сообщение, на которое отвечают (для отображения)
  final bool isPinned; // ✅ Закреплено ли сообщение
  final List<MessageReaction>? reactions; // ✅ Реакции на сообщение
  final bool isForwarded; // ✅ Переслано ли сообщение
  final String? originalChatName; // ✅ Название оригинального чата (для пересланных)

  Message({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.content,
    this.imageUrl,
    this.originalImageUrl,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.fileMime,
    this.messageType = 'text',
    required this.senderEmail,
    required this.createdAt,
    this.deliveredAt,
    this.editedAt,
    this.isRead = false,
    this.readAt,
    this.replyToMessageId,
    this.replyToMessage,
    this.isPinned = false,
    this.reactions,
    this.isForwarded = false,
    this.originalChatName,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasOriginalImage => originalImageUrl != null && originalImageUrl!.isNotEmpty;
  bool get hasFile => fileUrl != null && fileUrl!.isNotEmpty;
  bool get isFileOnly => messageType == 'file' || (hasFile && content.isEmpty);
  bool get isImageOnly => messageType == 'image' || (hasImage && content.isEmpty);
  bool get hasText => content.isNotEmpty;
  bool get isEdited => editedAt != null && editedAt!.isNotEmpty;
  
  // ✅ Статус сообщения для отображения
  MessageStatus get status {
    if (isRead) return MessageStatus.read;
    if (deliveredAt != null) return MessageStatus.delivered;
    return MessageStatus.sent;
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    try {
      return Message(
        id: (json['id'] ?? '').toString(),
        chatId: (json['chat_id'] ?? '').toString(),
        userId: (json['user_id'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
        imageUrl: json['image_url'] as String?,
        originalImageUrl: json['original_image_url'] as String?,
        fileUrl: json['file_url'] as String?,
        fileName: json['file_name'] as String?,
        fileSize: json['file_size'] is int ? (json['file_size'] as int) : int.tryParse((json['file_size'] ?? '').toString()),
        fileMime: json['file_mime'] as String?,
        messageType: json['message_type'] ?? 'text',
        senderEmail: (json['sender_email'] ?? '').toString(),
        createdAt: json['created_at']?.toString() ?? '',
        deliveredAt: json['delivered_at']?.toString(),
        editedAt: json['edited_at']?.toString(),
        isRead: json['is_read'] == true || json['is_read'] == 1,
        readAt: json['read_at']?.toString(),
        replyToMessageId: json['reply_to_message_id']?.toString(),
        replyToMessage: json['reply_to_message'] != null 
            ? Message.fromJson(json['reply_to_message'] as Map<String, dynamic>)
            : null,
        isPinned: json['is_pinned'] == true || json['is_pinned'] == 1,
        reactions: json['reactions'] != null
            ? (json['reactions'] as List).map((r) => MessageReaction.fromJson(r)).toList()
            : null,
        isForwarded: json['is_forwarded'] == true || json['is_forwarded'] == 1,
        originalChatName: json['original_chat_name'] as String?,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing Message from JSON: $e');
        print('JSON: $json');
      }
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'user_id': userId,
      'content': content,
      'image_url': imageUrl,
      'original_image_url': originalImageUrl,
      'file_url': fileUrl,
      'file_name': fileName,
      'file_size': fileSize,
      'file_mime': fileMime,
      'message_type': messageType,
      'sender_email': senderEmail,
      'created_at': createdAt,
      'delivered_at': deliveredAt,
      'edited_at': editedAt,
      'is_read': isRead,
      'read_at': readAt,
      'reply_to_message_id': replyToMessageId,
      'reply_to_message': replyToMessage?.toJson(),
      'is_pinned': isPinned,
      'reactions': reactions?.map((r) => r.toJson()).toList(),
      'is_forwarded': isForwarded,
      'original_chat_name': originalChatName,
    };
  }
}

// ✅ Enum для статусов сообщений
enum MessageStatus {
  sent,      // Отправлено (один чек)
  delivered, // Доставлено (два чека)
  read,      // Прочитано (два синих чека)
}

// ✅ Модель реакции на сообщение
class MessageReaction {
  final String id;
  final String messageId;
  final String userId;
  final String reaction; // Эмодзи
  final String createdAt;
  final String? userEmail; // Email пользователя, поставившего реакцию

  MessageReaction({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.reaction,
    required this.createdAt,
    this.userEmail,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      id: (json['id'] ?? '').toString(),
      messageId: (json['message_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      reaction: json['reaction'] ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      userEmail: json['user_email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message_id': messageId,
      'user_id': userId,
      'reaction': reaction,
      'created_at': createdAt,
      'user_email': userEmail,
    };
  }
}
