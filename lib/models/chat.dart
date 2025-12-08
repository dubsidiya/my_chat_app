class Chat {
  final String id;
  final String name;
  final bool isGroup;

  Chat({required this.id, required this.name, required this.isGroup});

  factory Chat.fromJson(Map<String, dynamic> json) {
    try {
      return Chat(
        id: (json['id'] ?? '').toString(),
        name: json['name'] ?? '',
        isGroup: _parseBool(json['is_group']),
      );
    } catch (e) {
      print('Error parsing Chat from JSON: $e');
      print('JSON: $json');
      rethrow;
    }
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return false;
  }
}



