import 'package:flutter/foundation.dart' show kDebugMode;

class Chat {
  final String id;
  final String name;
  final bool isGroup;
  /// Папка для текущего пользователя (ID) или null
  final String? folderId;
  /// Имя папки (для отображения) или null
  final String? folderName;
  /// ID собеседника (для личных чатов)
  final String? otherUserId;
  /// Аватар собеседника (для личных чатов)
  final String? otherUserAvatarUrl;
  final String? lastMessageId;
  final String? lastMessageText;
  final String? lastMessageType;
  final String? lastMessageImageUrl;
  final String? lastMessageFileUrl;
  final String? lastMessageFileName;
  final int? lastMessageFileSize;
  final String? lastMessageFileMime;
  final String? lastMessageAt;
  final String? lastSenderEmail;
  final int unreadCount;

  Chat({
    required this.id,
    required this.name,
    required this.isGroup,
    this.folderId,
    this.folderName,
    this.otherUserId,
    this.otherUserAvatarUrl,
    this.lastMessageId,
    this.lastMessageText,
    this.lastMessageType,
    this.lastMessageImageUrl,
    this.lastMessageFileUrl,
    this.lastMessageFileName,
    this.lastMessageFileSize,
    this.lastMessageFileMime,
    this.lastMessageAt,
    this.lastSenderEmail,
    this.unreadCount = 0,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    try {
      final last = json['last_message'];
      final Map<String, dynamic>? lastMap =
          last is Map ? last.cast<String, dynamic>() : null;

      return Chat(
        id: (json['id'] ?? '').toString(),
        name: json['name'] ?? '',
        isGroup: _parseBool(json['is_group']),
        folderId: (json['folder_id'] ?? json['folderId'] ?? json['folder'])?.toString(),
        folderName: (json['folder_name'] ?? json['folderName'])?.toString(),
        otherUserId: (json['other_user_id'] ?? json['otherUserId'])?.toString(),
        otherUserAvatarUrl: (json['other_user_avatar_url'] ?? json['otherUserAvatarUrl'])?.toString(),
        unreadCount: _parseInt(json['unread_count']),
        lastMessageId: lastMap?['id']?.toString(),
        lastMessageText: lastMap?['content']?.toString(),
        lastMessageType: lastMap?['message_type']?.toString(),
        lastMessageImageUrl: lastMap?['image_url']?.toString(),
        lastMessageFileUrl: lastMap?['file_url']?.toString(),
        lastMessageFileName: lastMap?['file_name']?.toString(),
        lastMessageFileSize: lastMap?['file_size'] is int
            ? (lastMap?['file_size'] as int)
            : int.tryParse((lastMap?['file_size'] ?? '').toString()),
        lastMessageFileMime: lastMap?['file_mime']?.toString(),
        lastMessageAt: lastMap?['created_at']?.toString(),
        lastSenderEmail: lastMap?['sender_email']?.toString(),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing Chat from JSON: $e');
        print('JSON: $json');
      }
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

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}



