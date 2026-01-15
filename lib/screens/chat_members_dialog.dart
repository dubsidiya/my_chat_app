import 'package:flutter/material.dart';
import '../services/chats_service.dart';

class ChatMembersDialog extends StatefulWidget {
  final List<Map<String, dynamic>> members;
  final String currentUserId;
  final String chatId;
  final ChatsService chatsService;

  const ChatMembersDialog({
    required this.members,
    required this.currentUserId,
    required this.chatId,
    required this.chatsService,
  });

  @override
  State<ChatMembersDialog> createState() => _ChatMembersDialogState();
}

class _ChatMembersDialogState extends State<ChatMembersDialog> {
  static const Color _accent1 = Color(0xFF667eea);
  static const Color _accent2 = Color(0xFF764ba2);
  static const Color _accent3 = Color(0xFFf093fb);

  List<Map<String, dynamic>> _members = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _members = List.from(widget.members);
  }

  Future<void> _removeMember(String userId, String userEmail) async {
    // Проверяем, является ли пользователь создателем
    final member = _members.firstWhere(
      (m) => m['id'] == userId,
      orElse: () => {},
    );
    
    final isCreator = member['is_creator'] == true || member['is_creator'] == 1;
    
    // Не позволяем удалить создателя чата
    if (isCreator) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Нельзя удалить создателя чата'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Показываем диалог подтверждения
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Удалить участника?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text('Вы уверены, что хотите удалить "$userEmail" из чата?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.chatsService.removeMemberFromChat(widget.chatId, userId);
      
      if (mounted) {
        // Удаляем участника из списка
        setState(() {
          _members.removeWhere((m) => m['id'] == userId);
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Участник "$userEmail" удален из чата'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Ошибка удаления участника: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении участника: ${e.toString().replaceFirst('Exception: ', '')}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titlePadding: EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: EdgeInsets.fromLTRB(20, 12, 20, 12),
      actionsPadding: EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_accent1, _accent2]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _accent1.withOpacity(0.25),
                  blurRadius: 10,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Icon(Icons.groups_rounded, color: Colors.white, size: 22),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Участники чата',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _accent1.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${_members.length}',
              style: TextStyle(
                color: _accent1,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_accent1),
                strokeWidth: 3,
              ),
            )
          : SizedBox(
              width: double.maxFinite,
              child: _members.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _accent1.withOpacity(0.15),
                                  _accent3.withOpacity(0.15),
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.group_off_rounded,
                              size: 42,
                              color: _accent1.withOpacity(0.7),
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Нет участников',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        final userId = member['id'] as String;
                        final email = member['email'] as String;
                        final isCreator = member['is_creator'] == true || member['is_creator'] == 1;

                        return Container(
                          margin: EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.grey.shade200, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isCreator ? [_accent1, _accent2] : [_accent3, _accent2],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Center(
                                    child: Text(
                                      email.isNotEmpty ? email[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade900,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      if (isCreator)
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _accent1.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'Создатель чата',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _accent1,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (!isCreator)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade500),
                                      onPressed: () => _removeMember(userId, email),
                                      tooltip: 'Удалить участника',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          child: Text(
            'Закрыть',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }
}

