class Message {
  final String id;
  final String chatId;
  final String userId;
  final String content;
  final String? imageUrl;
  final String? originalImageUrl; // ✅ URL оригинального изображения
  final String messageType; // 'text', 'image', 'text_image'
  final String senderEmail;
  final String createdAt;
  final String? deliveredAt; // ✅ Время доставки
  final String? editedAt; // ✅ Время редактирования
  final bool isRead; // ✅ Прочитано ли сообщение текущим пользователем
  final String? readAt; // ✅ Время прочтения

  Message({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.content,
    this.imageUrl,
    this.originalImageUrl,
    this.messageType = 'text',
    required this.senderEmail,
    required this.createdAt,
    this.deliveredAt,
    this.editedAt,
    this.isRead = false,
    this.readAt,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasOriginalImage => originalImageUrl != null && originalImageUrl!.isNotEmpty;
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
        content: json['content'] ?? '',
        imageUrl: json['image_url'] as String?,
        originalImageUrl: json['original_image_url'] as String?,
        messageType: json['message_type'] ?? 'text',
        senderEmail: json['sender_email'] ?? '',
        createdAt: json['created_at']?.toString() ?? '',
        deliveredAt: json['delivered_at']?.toString(),
        editedAt: json['edited_at']?.toString(),
        isRead: json['is_read'] == true || json['is_read'] == 1,
        readAt: json['read_at']?.toString(),
      );
    } catch (e) {
      print('Error parsing Message from JSON: $e');
      print('JSON: $json');
      rethrow;
    }
  }
}

// ✅ Enum для статусов сообщений
enum MessageStatus {
  sent,      // Отправлено (один чек)
  delivered, // Доставлено (два чека)
  read,      // Прочитано (два синих чека)
}
