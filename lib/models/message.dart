class Message {
  final String id;
  final String chatId;
  final String userId;
  final String content;
  final String? imageUrl;
  final String messageType; // 'text', 'image', 'text_image'
  final String senderEmail;
  final String createdAt;

  Message({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.content,
    this.imageUrl,
    this.messageType = 'text',
    required this.senderEmail,
    required this.createdAt,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get isImageOnly => messageType == 'image' || (hasImage && content.isEmpty);
  bool get hasText => content.isNotEmpty;

  factory Message.fromJson(Map<String, dynamic> json) {
    try {
      return Message(
        id: (json['id'] ?? '').toString(),
        chatId: (json['chat_id'] ?? '').toString(),
        userId: (json['user_id'] ?? '').toString(),
        content: json['content'] ?? '',
        imageUrl: json['image_url'] as String?,
        messageType: json['message_type'] ?? 'text',
        senderEmail: json['sender_email'] ?? '',
        createdAt: json['created_at']?.toString() ?? '',
      );
    } catch (e) {
      print('Error parsing Message from JSON: $e');
      print('JSON: $json');
      rethrow;
    }
  }
}
