import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/message.dart';
import '../services/messages_service.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String chatId;
  final String chatName;

  const ChatScreen({
    required this.userId,
    required this.userEmail,
    required this.chatId,
    required this.chatName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messagesService = MessagesService();
  late WebSocketChannel _channel;

  List<Message> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _channel = WebSocketChannel.connect(
      Uri.parse('wss://my-server-chat.onrender.com'),
    );

    _channel.stream.listen((event) {
      final data = jsonDecode(event);
      if (data['chat_id'] == widget.chatId) {
        setState(() {
          _messages.add(Message.fromJson(data));
        });
      }
    });

    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final messages = await _messagesService.fetchMessages(widget.chatId);
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
      await _messagesService.sendMessage(widget.userId, widget.chatId, text);
      _controller.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки сообщения')),
      );
    }
  }

  @override
  void dispose() {
    _channel.sink.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chatName)),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[_messages.length - 1 - index];
                final isMine = msg.senderEmail == widget.userEmail;

                return Align(
                  alignment:
                  isMine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMine
                          ? Colors.blueAccent
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.content,
                          style: TextStyle(
                            color: isMine ? Colors.white : Colors.black87,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          msg.createdAt,
                          style: TextStyle(
                            fontSize: 10,
                            color: isMine
                                ? Colors.white70
                                : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration:
                    InputDecoration(hintText: 'Введите сообщение...'),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
