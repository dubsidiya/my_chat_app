import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/chats_service.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String userEmail;

  HomeScreen({required this.userId, required this.userEmail});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ChatsService _chatsService = ChatsService();
  List<Chat> _chats = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    setState(() => _isLoading = true);
    try {
      final chats = await _chatsService.fetchChats(widget.userId);
      setState(() => _chats = chats);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при загрузке чатов')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _openChat(Chat chat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: widget.userId,
          userEmail: widget.userEmail,
          chatId: chat.id,
          chatName: chat.name,
        ),
      ),
    );
  }

  Future<void> _showCreateChatDialog() async {
    final TextEditingController _nameController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Создать чат'),
          content: TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: 'Имя чата'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = _nameController.text.trim();
                if (name.isEmpty) return;

                // Сейчас для упрощения добавляем только текущего пользователя в чат
                final success = await _chatsService.createChat(name, [widget.userId]);

                if (success==null) {
                  Navigator.pop(context);
                  _loadChats();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка при создании чата')),
                  );
                }
              },
              child: Text('Создать'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Мои чаты'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadChats,
          ),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showCreateChatDialog,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _chats.isEmpty
          ? Center(child: Text('Нет доступных чатов'))
          : ListView.builder(
        itemCount: _chats.length,
        itemBuilder: (context, index) {
          final chat = _chats[index];
          return ListTile(
            leading: Icon(chat.isGroup ? Icons.group : Icons.person),
            title: Text(chat.name),
            onTap: () => _openChat(chat),
          );
        },
      ),
    );
  }
}
