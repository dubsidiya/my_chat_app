class ChatMediaItem {
  final String id;
  final String chatId;
  final String userId;
  final String content;
  final String? imageUrl;
  final String? originalImageUrl;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String? fileMime;
  final String messageType;
  final String createdAt;

  ChatMediaItem({
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
    required this.messageType,
    required this.createdAt,
  });

  bool get isImage => (imageUrl ?? '').trim().isNotEmpty;

  bool get isVideo {
    final m = (fileMime ?? '').toLowerCase().trim();
    if (m.startsWith('video/')) return true;
    final n = (fileName ?? '').toLowerCase().trim();
    return n.endsWith('.mp4') || n.endsWith('.mov') || n.endsWith('.m4v') || n.endsWith('.webm') || n.endsWith('.mkv');
  }

  String? get bestImageUrl {
    final o = (originalImageUrl ?? '').trim();
    if (o.isNotEmpty) return o;
    final c = (imageUrl ?? '').trim();
    if (c.isNotEmpty) return c;
    return null;
  }

  factory ChatMediaItem.fromJson(Map<String, dynamic> json) {
    return ChatMediaItem(
      id: (json['id'] ?? '').toString(),
      chatId: (json['chat_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      imageUrl: json['image_url']?.toString(),
      originalImageUrl: json['original_image_url']?.toString(),
      fileUrl: json['file_url']?.toString(),
      fileName: json['file_name']?.toString(),
      fileSize: json['file_size'] is int ? json['file_size'] as int : int.tryParse((json['file_size'] ?? '').toString()),
      fileMime: json['file_mime']?.toString(),
      messageType: (json['message_type'] ?? 'text').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}

