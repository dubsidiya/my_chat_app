import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

import '../services/messages_service.dart';

class ChatScreen extends StatefulWidget {
  final String userId;

  ChatScreen({required this.userId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessagesService _messagesService = MessagesService();
  final TextEditingController _controller = TextEditingController();
  late WebSocketChannel _channel;

  List<Message> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _channel = WebSocketChannel.connect(
      Uri.parse('wss://my-server-chat.onrender.com'),
    );

    _channel.stream.listen((message) {
      final data = jsonDecode(message);
      setState(() {
        _messages.add(Message.fromJson(data));
      });
    });

    _loadMessages(); // начальная загрузка истории
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final messages = await _messagesService.fetchMessages();
      setState(() => _messages = messages);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки сообщений')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    try {
      await _messagesService.sendMessage(widget.userId, text);
      _controller.clear();
      // не нужно вручную обновлять список, так как WebSocket получит новое сообщение
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки сообщения')),
      );
    }
  }

  @override
  void dispose() {
    _channel.sink.close(); // закрываем WebSocket
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Чат')),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                return ListTile(
                  title: Text(message.content),
                  subtitle: Text(
                    'От: ${message.senderEmail} • ${message.createdAt}',
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Введите сообщение',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendMessage,
                  child: Text('Отправить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
