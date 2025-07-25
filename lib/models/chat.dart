class Chat {
  final String id;
  final String name;
  final bool isGroup;

  Chat({required this.id, required this.name, required this.isGroup});

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'].toString(),
      name: json['name'],
      isGroup: (json['is_group'] ?? false) is bool
          ? (json['is_group'] ?? false) as bool
          : (json['is_group'] ?? 0) == 1,
    );
  }
}

