import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../services/chats_service.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String userEmail;

  const HomeScreen({required this.userId, required this.userEmail});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _chatsService = ChatsService();
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
        SnackBar(content: Text('Ошибка загрузки чатов')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ваши чаты')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _chats.length,
        itemBuilder: (context, index) {
          final chat = _chats[index];
          return ListTile(
            title: Text(chat.name),
            subtitle: Text(chat.isGroup ? 'Групповой чат' : 'Личный чат'),
            onTap: () => _openChat(chat),
          );
        },
      ),
    );
  }
}
