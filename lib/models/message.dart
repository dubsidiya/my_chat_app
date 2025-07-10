class Message {
  final int id;
  final String content;
  final String senderEmail;
  final String createdAt;

  Message({
    required this.id,
    required this.content,
    required this.senderEmail,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      content: json['content'],
      senderEmail: json['sender_email'], // имей в виду ключи чувствительны
      createdAt: json['created_at'],
    );
  }
}
