class ChatFolder {
  final String id;
  final String name;

  ChatFolder({
    required this.id,
    required this.name,
  });

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    return ChatFolder(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
    );
  }
}

