class Message {
  final int id;
  final String userId;
  final String content;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'],
    userId: json['user_id'],
    content: json['content'],
    createdAt: DateTime.parse(json['created_at']),
  );
}
