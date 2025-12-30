import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

import '../models/message.dart';
import '../services/messages_service.dart';
import '../services/chats_service.dart';
import '../services/storage_service.dart';
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
  final _scrollController = ScrollController();
  final _messagesService = MessagesService();
  final _chatsService = ChatsService();
  WebSocketChannel? _channel;
  StreamSubscription? _webSocketSubscription;

  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  String? _oldestMessageId;
  static const int _messagesPerPage = 50;
  String? _selectedImagePath;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();

    // Инициализируем WebSocket асинхронно
    _initWebSocket();
    
    _loadMessages();
  }

  void _setupWebSocketListener() {
    if (_channel == null) return;
    _webSocketSubscription = _channel!.stream.listen(
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

    // Добавляем listener для автоматической подгрузки при скролле вверх
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initWebSocket() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        print('WebSocket: No token available');
        return;
      }

      // Подключаемся к WebSocket с токеном
      _channel = WebSocketChannel.connect(
        Uri.parse('wss://my-server-chat.onrender.com?token=$token'),
      );
      
      // Настраиваем слушатель после подключения
      if (mounted) {
        _setupWebSocketListener();
      }
    } catch (e) {
      print('Error initializing WebSocket: $e');
    }
  }

  void _onScroll() {
    // В reverse списке: когда прокрутили почти до верха (к старшим сообщениям)
    // minScrollExtent = 0 (верх списка, где старые сообщения)
    // maxScrollExtent = низ списка (где новые сообщения)
    if (_scrollController.position.pixels <= 300) {
      if (!_isLoadingMore && _hasMoreMessages && _messages.isNotEmpty) {
        _loadMoreMessages();
      }
    }
  }

  Future<void> _loadMessages() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasMoreMessages = true;
      _oldestMessageId = null;
    });
    
    try {
      final result = await _messagesService.fetchMessagesPaginated(
        widget.chatId,
        limit: _messagesPerPage,
        offset: 0,
      );
      
      if (mounted) {
        setState(() {
          _messages = result.messages;
          _hasMoreMessages = result.hasMore;
          _oldestMessageId = result.oldestMessageId;
        });
        
        // Прокручиваем вниз после загрузки
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
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

  Future<void> _loadMoreMessages() async {
    if (!mounted || _isLoadingMore || !_hasMoreMessages) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      // Сохраняем текущую позицию скролла и максимальную высоту контента
      final currentScrollPosition = _scrollController.position.pixels;
      final maxScrollExtentBefore = _scrollController.position.maxScrollExtent;
      
      // Загружаем старые сообщения
      final result = await _messagesService.fetchMessagesPaginated(
        widget.chatId,
        limit: _messagesPerPage,
        beforeMessageId: _oldestMessageId,
      );
      
      if (mounted && result.messages.isNotEmpty) {
        setState(() {
          // Добавляем новые сообщения в начало списка
          _messages.insertAll(0, result.messages);
          // Удаляем дубликаты (на случай если сообщение уже есть)
          final seen = <String>{};
          _messages.removeWhere((msg) {
            final id = msg.id.toString();
            if (seen.contains(id)) {
              return true;
            }
            seen.add(id);
            return false;
          });
          // Сортируем по времени
          _messages.sort((a, b) {
            try {
              final aTime = DateTime.parse(a.createdAt);
              final bTime = DateTime.parse(b.createdAt);
              return aTime.compareTo(bTime);
            } catch (e) {
              return 0;
            }
          });
          
          _hasMoreMessages = result.hasMore;
          _oldestMessageId = result.oldestMessageId;
        });
        
        // Восстанавливаем позицию скролла после добавления сообщений
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && mounted) {
            // Вычисляем разницу в высоте контента
            final maxScrollExtentAfter = _scrollController.position.maxScrollExtent;
            final heightDifference = maxScrollExtentAfter - maxScrollExtentBefore;
            
            // Новая позиция = старая позиция + разница в высоте
            // Это сохраняет видимую позицию пользователя
            final newScrollPosition = currentScrollPosition + heightDifference;
            
            // Прокручиваем к новой позиции
            _scrollController.jumpTo(
              newScrollPosition.clamp(0.0, _scrollController.position.maxScrollExtent),
            );
          }
        });
      } else if (mounted) {
        // Если нет новых сообщений, значит больше загружать нечего
        setState(() {
          _hasMoreMessages = false;
        });
      }
    } catch (e) {
      print('Error loading more messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки сообщений: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
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

  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, // Используем custom для указания расширений
        allowMultiple: false,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'], // Явно указываем разрешенные расширения
      );

      if (result != null && result.files.single.size > 0) {
        final file = result.files.single;
        
        // Проверяем расширение файла на клиенте
        final fileName = file.name.toLowerCase();
        final allowedExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
        final hasValidExtension = allowedExtensions.any((ext) => fileName.endsWith(ext));
        
        if (!hasValidExtension) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Неподдерживаемый формат файла. Используйте: JPEG, JPG, PNG, GIF, WEBP'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        
        if (kIsWeb) {
          // На веб используем bytes
          if (file.bytes != null) {
            setState(() {
              _selectedImageBytes = file.bytes;
              _selectedImageName = file.name;
              _selectedImagePath = null; // На веб path недоступен
            });
          }
        } else {
          // На мобильных/десктоп используем path
          if (file.path != null) {
            setState(() {
              _selectedImagePath = file.path;
              _selectedImageBytes = null;
              _selectedImageName = file.name;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора изображения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final hasImage = _selectedImagePath != null || _selectedImageBytes != null;
    if (text.isEmpty && !hasImage || !mounted) return;

    String? imageUrl;

    // Загружаем изображение, если выбрано
    if (hasImage) {
      setState(() => _isUploadingImage = true);
      try {
        Uint8List bytes;
        String fileName;
        
        if (kIsWeb) {
          // На веб используем bytes напрямую
          if (_selectedImageBytes != null) {
            bytes = _selectedImageBytes!;
            fileName = _selectedImageName ?? 'image.jpg';
          } else {
            throw Exception('Изображение не выбрано');
          }
        } else {
          // На мобильных/десктоп читаем из файла
          if (_selectedImagePath != null) {
            final file = File(_selectedImagePath!);
            bytes = await file.readAsBytes();
            fileName = _selectedImagePath!.split('/').last;
          } else {
            throw Exception('Изображение не выбрано');
          }
        }
        
        imageUrl = await _messagesService.uploadImage(bytes, fileName);
      } catch (e) {
        if (mounted) {
          setState(() => _isUploadingImage = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки изображения: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      setState(() => _isUploadingImage = false);
    }

    try {
      await _messagesService.sendMessage(widget.chatId, text, imageUrl: imageUrl);
      if (mounted) {
        _controller.clear();
        setState(() {
          _selectedImagePath = null;
          _selectedImageBytes = null;
          _selectedImageName = null;
        });
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _webSocketSubscription?.cancel();
    _channel?.sink.close();
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
                : Stack(
              children: [
                ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: _messages.length + 
                      (_isLoadingMore ? 1 : 0) + 
                      (_hasMoreMessages && !_isLoadingMore && _messages.isNotEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    final totalItems = _messages.length + 
                        (_isLoadingMore ? 1 : 0) + 
                        (_hasMoreMessages && !_isLoadingMore && _messages.isNotEmpty ? 1 : 0);
                    
                    // Показываем индикатор загрузки вверху при подгрузке (в reverse списке это последний элемент)
                    if (_isLoadingMore && index == totalItems - 1) {
                      return Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 8),
                              Text(
                                'Загрузка сообщений...',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    
                    // Показываем кнопку "Загрузить еще" если есть еще сообщения
                    if (!_isLoadingMore && _hasMoreMessages && _messages.isNotEmpty && index == totalItems - 1) {
                      return Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: _loadMoreMessages,
                            icon: Icon(Icons.arrow_upward, size: 18),
                            label: Text('Загрузить старые сообщения'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      );
                    }
                    
                    // Индекс сообщения в списке (reverse: true, поэтому инвертируем)
                    // Учитываем дополнительные элементы (индикатор загрузки или кнопка)
                    final extraItems = (_isLoadingMore ? 1 : 0) + 
                        (_hasMoreMessages && !_isLoadingMore && _messages.isNotEmpty ? 1 : 0);
                    final messageIndex = _messages.length - 1 - (index - extraItems);
                    
                    if (messageIndex < 0 || messageIndex >= _messages.length) {
                      return SizedBox.shrink();
                    }
                    
                    final msg = _messages[messageIndex];
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
                                      color: isMine ? Colors.white70 : Colors.blue.shade700,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                ],
                                // Отображение изображения
                                if (msg.hasImage) ...[
                                  GestureDetector(
                                    onTap: () {
                                      // Открываем изображение в полноэкранном режиме
                                      showDialog(
                                        context: context,
                                        builder: (context) => Dialog(
                                          backgroundColor: Colors.transparent,
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: InteractiveViewer(
                                                  minScale: 0.5,
                                                  maxScale: 4.0,
                                                  child: Image.network(
                                                    msg.imageUrl!,
                                                    fit: BoxFit.contain,
                                                    headers: kIsWeb ? {
                                                      'Access-Control-Allow-Origin': '*',
                                                    } : {}, // Для веб добавляем CORS заголовки
                                                    errorBuilder: (context, error, stackTrace) {
                                                      print('Full screen image error: $error');
                                                      print('URL: ${msg.imageUrl}');
                                                      return Center(
                                                        child: Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Icon(Icons.error, color: Colors.white, size: 48),
                                                            SizedBox(height: 16),
                                                            Text('Ошибка загрузки изображения', style: TextStyle(color: Colors.white)),
                                                            SizedBox(height: 8),
                                                            Text('${msg.imageUrl}', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 40,
                                                right: 20,
                                                child: IconButton(
                                                  icon: Icon(Icons.close, color: Colors.white),
                                                  onPressed: () => Navigator.pop(context),
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: Colors.black54,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        msg.imageUrl!,
                                        width: 250,
                                        fit: BoxFit.cover,
                                        headers: kIsWeb ? {
                                          'Access-Control-Allow-Origin': '*',
                                        } : {}, // Для веб добавляем CORS заголовки
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            width: 250,
                                            height: 200,
                                            color: Colors.grey.shade200,
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                value: loadingProgress.expectedTotalBytes != null
                                                    ? loadingProgress.cumulativeBytesLoaded /
                                                        loadingProgress.expectedTotalBytes!
                                                    : null,
                                              ),
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          print('Image load error: $error');
                                          print('Image URL: ${msg.imageUrl}');
                                          print('Is Web: $kIsWeb');
                                          print('Stack trace: $stackTrace');
                                          if (kIsWeb) {
                                            print('⚠️  ВЕБ: Проверьте CORS настройки в Яндекс Облаке');
                                            print('   Убедитесь, что бакет публичный и CORS настроен');
                                          }
                                          return Container(
                                            width: 250,
                                            height: 200,
                                            color: Colors.grey.shade200,
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.error, color: Colors.red),
                                                SizedBox(height: 8),
                                                Text(
                                                  kIsWeb ? 'CORS ошибка?' : 'Ошибка загрузки',
                                                  style: TextStyle(fontSize: 12),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  'URL: ${msg.imageUrl?.substring(0, 50)}...',
                                                  style: TextStyle(fontSize: 10, color: Colors.grey),
                                                  textAlign: TextAlign.center,
                                                ),
                                                if (kIsWeb) ...[
                                                  SizedBox(height: 4),
                                                  Text(
                                                    'Проверьте CORS',
                                                    style: TextStyle(fontSize: 9, color: Colors.orange),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  if (msg.hasText) SizedBox(height: 8),
                                ],
                                // Отображение текста
                                if (msg.hasText) ...[
                                  Text(
                                    msg.content,
                                    style: TextStyle(
                                      color: isMine ? Colors.white : Colors.grey.shade900,
                                      fontSize: 15,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
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
              ],
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Превью выбранного изображения
                    if (_selectedImagePath != null || _selectedImageBytes != null)
                      Container(
                        margin: EdgeInsets.only(bottom: 8),
                        height: 100,
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: kIsWeb && _selectedImageBytes != null
                                  ? Image.memory(
                                      _selectedImageBytes!,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    )
                                  : _selectedImagePath != null
                                      ? Image.file(
                                          File(_selectedImagePath!),
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                        )
                                      : SizedBox.shrink(),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                icon: Icon(Icons.close, color: Colors.white),
                                onPressed: () {
                                  setState(() {
                                    _selectedImagePath = null;
                                    _selectedImageBytes = null;
                                    _selectedImageName = null;
                                  });
                                },
                                iconSize: 20,
                                padding: EdgeInsets.all(4),
                                constraints: BoxConstraints(),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        // Кнопка выбора изображения
                        IconButton(
                          icon: Icon(Icons.image, color: Colors.blue),
                          onPressed: _pickImage,
                          tooltip: 'Прикрепить изображение',
                        ),
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
                        // Кнопка отправки
                        if (_isUploadingImage)
                          Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
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
