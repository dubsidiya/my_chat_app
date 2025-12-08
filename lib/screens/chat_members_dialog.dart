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
        title: Text('Удалить участника?'),
        content: Text('Вы уверены, что хотите удалить "$userEmail" из чата?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
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
      title: Text('Участники чата (${_members.length})'),
      content: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SizedBox(
              width: double.maxFinite,
              child: _members.isEmpty
                  ? Center(child: Text('Нет участников'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        final userId = member['id'] as String;
                        final email = member['email'] as String;
                        final isCreator = member['is_creator'] == true || member['is_creator'] == 1;

                        return ListTile(
                          leading: Icon(
                            isCreator ? Icons.person : Icons.account_circle,
                            color: isCreator ? Colors.blue : Colors.grey,
                          ),
                          title: Text(
                            email,
                            style: TextStyle(
                              fontWeight: isCreator ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: isCreator ? Text('Создатель чата') : null,
                          trailing: isCreator
                              ? null
                              : IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _removeMember(userId, email),
                                  tooltip: 'Удалить участника',
                                ),
                        );
                      },
                    ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Закрыть'),
        ),
      ],
    );
  }
}

