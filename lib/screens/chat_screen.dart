import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';

import '../models/message.dart';
import '../services/messages_service.dart';
import '../services/chats_service.dart';
import 'add_members_dialog.dart';
import 'chat_members_dialog.dart';

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
  final _chatsService = ChatsService();
  late WebSocketChannel _channel;
  StreamSubscription? _webSocketSubscription;

  List<Message> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    // Подключаемся к WebSocket с userId в query параметре
    _channel = WebSocketChannel.connect(
      Uri.parse('wss://my-server-chat.onrender.com?userId=${widget.userId}'),
    );

    _webSocketSubscription = _channel.stream.listen(
      (event) {
        if (!mounted) return;
        try {
          print('WebSocket received: $event');
          final data = jsonDecode(event);
          print('Parsed WebSocket data: $data');
          
          // Проверяем тип сообщения
          final messageType = data['type'];
          
          if (messageType == 'message_deleted') {
            // Обработка уведомления об удалении сообщения
            final deletedMessageId = data['message_id']?.toString();
            final chatId = data['chat_id']?.toString();
            final currentChatId = widget.chatId.toString();
            
            if (chatId == currentChatId && deletedMessageId != null) {
              print('Message deleted notification: $deletedMessageId');
              if (mounted) {
                setState(() {
                  _messages.removeWhere((m) => m.id.toString() == deletedMessageId);
                  print('Message removed from list. Remaining messages: ${_messages.length}');
                });
              }
            }
            return;
          }
          
          // Проверяем, что это сообщение для текущего чата
          // Преобразуем chat_id в строку для сравнения
          final chatId = data['chat_id']?.toString() ?? data['chatId']?.toString();
          final currentChatId = widget.chatId.toString();
          
          print('WebSocket chat_id: $chatId, current chat_id: $currentChatId');
          
          if (chatId == currentChatId) {
            print('Message is for current chat');
            try {
              final message = Message.fromJson(data);
              print('Parsed message: ${message.id} - ${message.content}');
              
              if (mounted) {
                setState(() {
                  // Проверяем, нет ли уже такого сообщения (избегаем дубликатов)
                  final exists = _messages.any((m) => m.id == message.id);
                  if (!exists) {
                    _messages.add(message);
                    // Сортируем сообщения по времени после добавления
                    _messages.sort((a, b) {
                      try {
                        final aTime = DateTime.parse(a.createdAt);
                        final bTime = DateTime.parse(b.createdAt);
                        return aTime.compareTo(bTime);
                      } catch (e) {
                        return 0;
                      }
                    });
                    print('Message added to list. Total messages: ${_messages.length}');
                  } else {
                    print('Message already exists, skipping');
                  }
                });
              }
            } catch (parseError) {
              print('Error parsing Message from WebSocket data: $parseError');
              print('Data: $data');
            }
          } else {
            print('Message is for different chat: $chatId (current: $currentChatId)');
          }
        } catch (e) {
          print('Error processing WebSocket message: $e');
          print('Raw event: $event');
        }
      },
      onError: (error) {
        print('WebSocket error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка WebSocket: $error')),
          );
        }
      },
      onDone: () {
        print('WebSocket connection closed');
      },
    );

    _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final messages = await _messagesService.fetchMessages(widget.chatId);
      if (mounted) {
      setState(() => _messages = messages);
      }
    } catch (e) {
      print('Error loading messages: $e');
      if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки сообщений: $e')),
      );
      }
    } finally {
      if (mounted) {
      setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        // Сегодня - показываем только время
        return DateFormat('HH:mm').format(date);
      } else if (difference.inDays == 1) {
        // Вчера
        return 'Вчера ${DateFormat('HH:mm').format(date)}';
      } else if (difference.inDays < 7) {
        // На этой неделе - показываем день недели и время
        final weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
        final weekday = weekdays[date.weekday - 1];
        return '$weekday ${DateFormat('HH:mm').format(date)}';
      } else {
        // Старше недели - показываем полную дату
        return DateFormat('dd.MM.yyyy HH:mm').format(date);
      }
    } catch (e) {
      // Если не удалось распарсить, возвращаем как есть
      return dateString;
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !mounted) return;

    try {
      await _messagesService.sendMessage(widget.userId, widget.chatId, text);
      if (mounted) {
      _controller.clear();
      }
    } catch (e) {
      print('Error sending message: $e');
      if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки сообщения: $e')),
      );
      }
    }
  }

  Future<void> _showDeleteMessageDialog(Message message) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить сообщение?'),
        content: Text('Вы уверены, что хотите удалить это сообщение?'),
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

    try {
      await _messagesService.deleteMessage(message.id.toString(), widget.userId);
      
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == message.id);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Сообщение удалено'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Ошибка удаления сообщения: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении сообщения: ${e.toString().replaceFirst('Exception: ', '')}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _clearChat() async {
    if (!mounted) return;

    // Показываем диалог подтверждения
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Очистить чат?'),
        content: Text('Вы уверены, что хотите удалить все сообщения из этого чата? Это действие нельзя отменить.'),
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
            child: Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _messagesService.clearChat(widget.chatId, widget.userId);
      
      if (mounted) {
        // Очищаем список сообщений
        setState(() {
          _messages.clear();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Чат успешно очищен'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Ошибка очистки чата: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при очистке чата: ${e.toString().replaceFirst('Exception: ', '')}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _webSocketSubscription?.cancel();
    _channel.sink.close();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showMembersDialog() async {
    if (!mounted) return;
    
    try {
      // Получаем участников чата
      final members = await _chatsService.getChatMembers(widget.chatId);
      
      if (!mounted) return;
      
      // Показываем диалог со списком участников
      await showDialog(
        context: context,
        builder: (context) => ChatMembersDialog(
          members: members,
          currentUserId: widget.userId,
          chatId: widget.chatId,
          chatsService: _chatsService,
        ),
      );
    } catch (e) {
      print('Ошибка загрузки участников: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при загрузке участников: ${e.toString().replaceFirst('Exception: ', '')}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _showAddMembersDialog() async {
    if (!mounted) return;
    
    try {
      // Получаем список всех пользователей
      final allUsers = await _chatsService.getAllUsers(widget.userId);
      
      // Получаем текущих участников чата
      final currentMembers = await _chatsService.getChatMembers(widget.chatId);
      final currentMemberIds = currentMembers.map((m) => m['id']).toSet();
      
      // Фильтруем пользователей, которые еще не в чате
      final availableUsers = allUsers
          .where((user) => !currentMemberIds.contains(user['id']))
          .toList();
      
      if (availableUsers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Нет доступных пользователей для добавления')),
          );
        }
        return;
      }
      
      // Показываем диалог выбора пользователей
      final selectedUsers = await showDialog<Set<String>>(
        context: context,
        builder: (context) => AddMembersDialog(availableUsers: availableUsers),
      );
      
      if (selectedUsers != null && selectedUsers.isNotEmpty && mounted) {
        try {
          await _chatsService.addMembersToChat(
            widget.chatId,
            selectedUsers.toList(),
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Участники успешно добавлены'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          print('Ошибка добавления участников: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка при добавлении участников: ${e.toString().replaceFirst('Exception: ', '')}'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Ошибка загрузки пользователей: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при загрузке списка пользователей: ${e.toString().replaceFirst('Exception: ', '')}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.chatName),
            Text(
              widget.userEmail,
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_sweep),
            onPressed: _clearChat,
            tooltip: 'Очистить чат',
          ),
          IconButton(
            icon: Icon(Icons.people),
            onPressed: _showMembersDialog,
            tooltip: 'Участники чата',
          ),
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: _showAddMembersDialog,
            tooltip: 'Добавить участников',
          ),
        ],
      ),
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

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment:
                        isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!isMine) ...[
                        // Аватар отправителя (только для чужих сообщений)
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.purple.shade400,
                                Colors.purple.shade600,
                              ],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              msg.senderEmail.isNotEmpty
                                  ? msg.senderEmail[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                      ],
                      Flexible(
                        child: GestureDetector(
                          onLongPress: isMine
                              ? () => _showDeleteMessageDialog(msg)
                              : null,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              gradient: isMine
                                  ? LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.blue.shade600,
                                        Colors.blue.shade700,
                                      ],
                                    )
                                  : null,
                              color: isMine ? null : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                                bottomLeft: Radius.circular(isMine ? 20 : 4),
                                bottomRight: Radius.circular(isMine ? 4 : 20),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isMine
                                          ? Colors.blue
                                          : Colors.grey)
                                      .withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                              border: isMine
                                  ? null
                                  : Border.all(
                                      color: Colors.grey.shade200,
                                      width: 1,
                                    ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Показываем отправителя только если это не ваше сообщение
                                if (!isMine) ...[
                                  Text(
                                    msg.senderEmail,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                ],
                                Text(
                                  msg.content,
                                  style: TextStyle(
                                    color: isMine ? Colors.white : Colors.grey.shade900,
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _formatDate(msg.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isMine
                                        ? Colors.white.withOpacity(0.8)
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isMine) ...[
                        SizedBox(width: 8),
                        // Аватар отправителя (для своих сообщений)
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.blue.shade400,
                                Colors.blue.shade600,
                              ],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              widget.userEmail.isNotEmpty
                                  ? widget.userEmail[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'Введите сообщение...',
                            hintStyle: TextStyle(color: Colors.grey.shade500),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.blue.shade600,
                            Colors.blue.shade700,
                          ],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(Icons.send, color: Colors.white),
                        onPressed: _sendMessage,
                        tooltip: 'Отправить',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
