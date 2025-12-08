class Message {
  final String id;
  final String chatId;
  final String userId;
  final String content;
  final String senderEmail;
  final String createdAt;

  Message({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.content,
    required this.senderEmail,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    try {
      return Message(
        id: (json['id'] ?? '').toString(),
        chatId: (json['chat_id'] ?? '').toString(),
        userId: (json['user_id'] ?? '').toString(),
        content: json['content'] ?? '',
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
