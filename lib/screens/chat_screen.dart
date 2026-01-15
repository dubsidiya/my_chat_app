import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';

import '../models/message.dart';
import '../services/messages_service.dart';
import '../services/chats_service.dart';
import '../services/storage_service.dart';
import '../services/local_messages_service.dart'; // ✅ Импорт сервиса кэширования
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
  static const Color _accent1 = Color(0xFF667eea);
  static const Color _accent2 = Color(0xFF764ba2);
  static const Color _accent3 = Color(0xFFf093fb);

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
  Message? _replyToMessage; // ✅ Сообщение, на которое отвечаем
  List<Message> _pinnedMessages = []; // ✅ Закрепленные сообщения

  @override
  void initState() {
    super.initState();

    // Инициализируем WebSocket асинхронно
    _initWebSocket();
    
    _loadMessages();
    _loadPinnedMessages(); // ✅ Загружаем закрепленные сообщения
    
    // ✅ Отмечаем все сообщения как прочитанные при открытии чата
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markChatAsRead();
    });
  }
  
  // ✅ Загрузить закрепленные сообщения
  Future<void> _loadPinnedMessages() async {
    try {
      final pinned = await _messagesService.getPinnedMessages(widget.chatId);
      if (mounted) {
        setState(() {
          _pinnedMessages = pinned;
        });
      }
    } catch (e) {
      print('Ошибка загрузки закрепленных сообщений: $e');
    }
  }
  
  // ✅ Отметить все сообщения в чате как прочитанные
  Future<void> _markChatAsRead() async {
    try {
      await _messagesService.markChatAsRead(widget.chatId);
    } catch (e) {
      print('Ошибка отметки чата как прочитанного: $e');
      // Не показываем ошибку пользователю, это не критично
    }
  }
  
  // ✅ Отметить конкретное сообщение как прочитанное
  // (функция была неиспользуемой; при необходимости можно вернуть и вызывать при отображении сообщения)

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
                
                // ✅ Удаляем сообщение из кэша
                LocalMessagesService.removeMessage(widget.chatId, deletedMessageId);
              }
            }
            return;
          }
          
          // ✅ Обработка события прочтения сообщения
          if (messageType == 'message_read') {
            final messageId = data['message_id']?.toString();
            if (messageId != null && mounted) {
              setState(() {
                final index = _messages.indexWhere((m) => m.id.toString() == messageId);
                if (index != -1) {
                  // Обновляем статус сообщения
                  final msg = _messages[index];
                  final updatedMessage = Message(
                    id: msg.id,
                    chatId: msg.chatId,
                    userId: msg.userId,
                    content: msg.content,
                    imageUrl: msg.imageUrl,
                    originalImageUrl: msg.originalImageUrl,
                    messageType: msg.messageType,
                    senderEmail: msg.senderEmail,
                    createdAt: msg.createdAt,
                    deliveredAt: msg.deliveredAt,
                    editedAt: msg.editedAt,
                    isRead: true,
                    readAt: data['read_at']?.toString() ?? DateTime.now().toIso8601String(),
                  );
                  _messages[index] = updatedMessage;
                  
                  // ✅ Обновляем в кэше
                  LocalMessagesService.updateMessage(widget.chatId, updatedMessage);
                }
              });
            }
            return;
          }
          
          // ✅ Обработка события прочтения нескольких сообщений
          if (messageType == 'messages_read') {
            final chatId = data['chat_id']?.toString();
            final currentChatId = widget.chatId.toString();
            if (chatId == currentChatId && mounted) {
              // Обновляем статусы всех сообщений текущего пользователя в этом чате
              setState(() {
                for (int i = 0; i < _messages.length; i++) {
                  final msg = _messages[i];
                  if (msg.userId == widget.userId) {
                    _messages[i] = Message(
                      id: msg.id,
                      chatId: msg.chatId,
                      userId: msg.userId,
                      content: msg.content,
                      imageUrl: msg.imageUrl,
                      originalImageUrl: msg.originalImageUrl,
                      messageType: msg.messageType,
                      senderEmail: msg.senderEmail,
                      createdAt: msg.createdAt,
                      deliveredAt: msg.deliveredAt,
                      editedAt: msg.editedAt,
                      isRead: true,
                      readAt: data['read_at']?.toString() ?? DateTime.now().toIso8601String(),
                    );
                  }
                }
              });
            }
            return;
          }
          
          // ✅ Обработка события редактирования сообщения
          if (messageType == 'message_edited') {
            final messageId = data['id']?.toString();
            final chatId = data['chat_id']?.toString();
            final currentChatId = widget.chatId.toString();
            
            if (chatId == currentChatId && messageId != null && mounted) {
              setState(() {
                final index = _messages.indexWhere((m) => m.id.toString() == messageId);
                if (index != -1) {
                  // Обновляем сообщение
                  final msg = _messages[index];
                  final updatedMessage = Message(
                    id: msg.id,
                    chatId: msg.chatId,
                    userId: msg.userId,
                    content: data['content'] ?? msg.content,
                    imageUrl: data['image_url'] ?? msg.imageUrl,
                    originalImageUrl: msg.originalImageUrl,
                    messageType: data['message_type'] ?? msg.messageType,
                    senderEmail: msg.senderEmail,
                    createdAt: msg.createdAt,
                    deliveredAt: msg.deliveredAt,
                    editedAt: data['edited_at']?.toString(),
                    isRead: msg.isRead,
                    readAt: msg.readAt,
                    replyToMessageId: msg.replyToMessageId,
                    replyToMessage: msg.replyToMessage,
                    isPinned: msg.isPinned,
                    reactions: msg.reactions,
                    isForwarded: msg.isForwarded,
                    originalChatName: msg.originalChatName,
                  );
                  _messages[index] = updatedMessage;
                  
                  // ✅ Обновляем в кэше
                  LocalMessagesService.updateMessage(widget.chatId, updatedMessage);
                }
              });
            }
            return;
          }
          
          // ✅ Обработка событий реакций
          if (messageType == 'reaction_added' || messageType == 'reaction_removed') {
            final messageId = data['message_id']?.toString();
            final reaction = data['reaction'] as String?;
            final userId = data['user_id']?.toString();
            
            if (messageId != null && mounted) {
              setState(() {
                final index = _messages.indexWhere((m) => m.id.toString() == messageId);
                if (index != -1) {
                  final msg = _messages[index];
                  final currentReactions = List<MessageReaction>.from(msg.reactions ?? []);
                  
                  if (messageType == 'reaction_added' && reaction != null) {
                    // Добавляем реакцию, если её еще нет
                    if (!currentReactions.any((r) => r.reaction == reaction && r.userId == userId)) {
                      currentReactions.add(MessageReaction(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        messageId: messageId,
                        userId: userId ?? '',
                        reaction: reaction,
                        createdAt: DateTime.now().toIso8601String(),
                        userEmail: data['user_email'] as String?,
                      ));
                    }
                  } else if (messageType == 'reaction_removed' && reaction != null) {
                    // Удаляем реакцию
                    currentReactions.removeWhere((r) => r.reaction == reaction && r.userId == userId);
                  }
                  
                  // Обновляем сообщение с новыми реакциями
                  _messages[index] = Message(
                    id: msg.id,
                    chatId: msg.chatId,
                    userId: msg.userId,
                    content: msg.content,
                    imageUrl: msg.imageUrl,
                    originalImageUrl: msg.originalImageUrl,
                    messageType: msg.messageType,
                    senderEmail: msg.senderEmail,
                    createdAt: msg.createdAt,
                    deliveredAt: msg.deliveredAt,
                    editedAt: msg.editedAt,
                    isRead: msg.isRead,
                    readAt: msg.readAt,
                    replyToMessageId: msg.replyToMessageId,
                    replyToMessage: msg.replyToMessage,
                    isPinned: msg.isPinned,
                    reactions: currentReactions,
                    isForwarded: msg.isForwarded,
                    originalChatName: msg.originalChatName,
                  );
                  
                  // Обновляем в кэше
                  LocalMessagesService.updateMessage(widget.chatId, _messages[index]);
                }
              });
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
                  // ✅ Проверяем, есть ли временное сообщение от текущего пользователя
                  // (чтобы заменить его на реальное сообщение от сервера)
                  final tempIndex = _messages.indexWhere((m) => 
                    m.id.startsWith('temp_') && 
                    m.userId == widget.userId.toString() &&
                    m.senderEmail == widget.userEmail &&
                    // Проверяем содержимое (текст или изображение)
                    ((m.content == message.content && m.content.isNotEmpty) ||
                     (m.imageUrl == message.imageUrl && m.imageUrl != null) ||
                     (m.content.isEmpty && m.imageUrl == null && message.content.isEmpty && message.imageUrl == null))
                  );
                  
                  if (tempIndex != -1) {
                    // ✅ Заменяем временное сообщение на реальное
                    print('✅ WebSocket: Replacing temp message at index $tempIndex with real message ${message.id}');
                    print('   Temp: ${_messages[tempIndex].id}, Real: ${message.id}');
                    
                    // ✅ Создаем новый список для принудительного обновления UI
                    final newMessages = List<Message>.from(_messages);
                    final tempId = newMessages[tempIndex].id; // Сохраняем ID временного сообщения
                    newMessages[tempIndex] = message;
                    
                    // ✅ Удаляем все остальные временные сообщения от этого пользователя
                    newMessages.removeWhere((m) => 
                      m.id.startsWith('temp_') && 
                      m.userId == widget.userId.toString() &&
                      m.id != tempId // НЕ удаляем то, что только что заменили
                    );
                    
                    _messages = newMessages;
                    print('✅ WebSocket: Message updated in UI. Total: ${_messages.length}');
                    
                    // ✅ Сохраняем в кэш с задержкой, чтобы не триггерить перезагрузку
                    Future.delayed(Duration(milliseconds: 500), () {
                      LocalMessagesService.updateMessage(widget.chatId, message);
                    });
                  } else {
                    // Проверяем, нет ли уже такого сообщения (избегаем дубликатов)
                    final exists = _messages.any((m) => m.id == message.id);
                    if (!exists) {
                      // ✅ Если это сообщение от текущего пользователя и недавно отправлено,
                      // возможно временное сообщение уже было удалено или не найдено
                      // В этом случае просто добавляем реальное сообщение
                      // НО: если это сообщение от текущего пользователя, возможно оно уже обновлено из ответа сервера
                      // Проверяем, нет ли временного сообщения с таким же содержимым
                      final hasMatchingTemp = _messages.any((m) => 
                        m.id.startsWith('temp_') && 
                        m.userId == widget.userId.toString() &&
                        ((m.content == message.content && m.content.isNotEmpty) ||
                         (m.imageUrl == message.imageUrl && m.imageUrl != null))
                      );
                      
                      if (hasMatchingTemp) {
                        // ✅ Есть временное сообщение - не добавляем дубликат, оно будет заменено выше
                        print('⚠️ WebSocket: Found matching temp message, skipping duplicate add');
                      } else {
                        // ✅ Добавляем сообщение только если нет временного
                        final newMessages = List<Message>.from(_messages);
                        newMessages.insert(0, message); // Добавляем в начало (reverse список)
                        _messages = newMessages;
                        print('✅ WebSocket: Message added to list. Total: ${_messages.length}');
                        
                        // ✅ Сохраняем новое сообщение в кэш с задержкой
                        Future.delayed(Duration(milliseconds: 500), () {
                          LocalMessagesService.addMessage(widget.chatId, message);
                        });
                      }
                    } else {
                      // ✅ Если сообщение уже есть, обновляем его и перемещаем в начало
                      final existingIndex = _messages.indexWhere((m) => m.id == message.id);
                      if (existingIndex != -1) {
                        // ✅ Обновляем сообщение на месте (может быть обновлена информация)
                        final newMessages = List<Message>.from(_messages);
                        newMessages[existingIndex] = message;
                        
                        if (existingIndex != 0) {
                          // Перемещаем в начало только если не в начале
                          newMessages.removeAt(existingIndex);
                          newMessages.insert(0, message);
                        }
                        
                        _messages = newMessages;
                        print('✅ WebSocket: Message updated at index $existingIndex. Total: ${_messages.length}');
                      } else {
                        print('⚠️ WebSocket: Message exists check failed, but index not found');
                      }
                    }
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
    
    // ✅ Сначала загружаем из кэша для быстрого отображения
    final existingTempMessages = _messages.where((m) => 
      m.id.startsWith('temp_') && 
      m.userId == widget.userId.toString()
    ).toList();
    
    try {
      final cachedMessages = await LocalMessagesService.getMessages(widget.chatId);
      if (cachedMessages.isNotEmpty && mounted) {
        setState(() {
          // ✅ Сохраняем временные сообщения при загрузке из кэша
          final cachedIds = cachedMessages.map((m) => m.id).toSet();
          final uniqueTempMessages = existingTempMessages.where((m) => !cachedIds.contains(m.id)).toList();
          // старые сверху, временные (новые) в конце
          _messages = [...cachedMessages, ...uniqueTempMessages];
        });
        print('✅ Загружено ${cachedMessages.length} сообщений из кэша');
      }
    } catch (e) {
      print('⚠️ Ошибка загрузки из кэша: $e');
    }
    
    // ✅ Затем загружаем с сервера и обновляем
    try {
      final result = await _messagesService.fetchMessagesPaginated(
        widget.chatId,
        limit: _messagesPerPage,
        offset: 0,
        useCache: false, // ✅ НЕ используем кэш при загрузке с сервера, чтобы не перезаписывать текущие сообщения
      );
      
      if (mounted) {
        setState(() {
          // ✅ Объединяем существующие сообщения с новыми (сохраняем временные сообщения)
          final currentTempMessages = _messages.where((m) => 
            m.id.startsWith('temp_') && 
            m.userId == widget.userId.toString()
          ).toList();
          final newMessages = result.messages;
          
          // ✅ Удаляем дубликаты и сохраняем временные сообщения
          final existingIds = newMessages.map((m) => m.id).toSet();
          final uniqueTempMessages = currentTempMessages.where((m) => !existingIds.contains(m.id)).toList();
          
          // старые сверху, новые снизу: серверные сообщения + временные в конце
          _messages = [...newMessages, ...uniqueTempMessages];
          _hasMoreMessages = result.hasMore;
          _oldestMessageId = result.oldestMessageId;
        });
        
        // Прокручиваем вниз (к новым сообщениям) после загрузки
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _messages.isNotEmpty) {
            final maxScroll = _scrollController.position.maxScrollExtent;
            if (maxScroll > 0) {
              _scrollController.jumpTo(maxScroll);
            }
          }
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
      // ✅ Если ошибка, но есть кэш - не показываем ошибку
      if (_messages.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки сообщений: $e'),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => _loadMessages(),
            ),
          ),
        );
      } else if (mounted) {
        // Показываем уведомление об офлайн режиме
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Офлайн режим. Показаны сохраненные сообщения.'),
            duration: Duration(seconds: 3),
          ),
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

  // ✅ Виджет для отображения статуса сообщения
  Widget _buildMessageStatus(Message msg) {
    final status = msg.status;
    IconData icon;
    Color color;
    
    switch (status) {
      case MessageStatus.sent:
        icon = Icons.check;
        color = Colors.white.withOpacity(0.6);
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = Colors.white.withOpacity(0.6);
        break;
      case MessageStatus.read:
        icon = Icons.done_all;
        color = Colors.blue.shade300; // Синий цвет для прочитанных
        break;
    }
    
    return Icon(
      icon,
      size: 14,
      color: color,
    );
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

  /// Сжатие изображения для уменьшения размера файла и использования памяти
  /// 
  /// [imageBytes] - оригинальные байты изображения
  /// [maxWidth] - максимальная ширина (по умолчанию 2560px для лучшего качества)
  /// [quality] - качество JPEG (0-100, по умолчанию 92 для высокого качества)
  /// 
  /// Возвращает сжатые байты изображения
  Future<Uint8List> _compressImage(Uint8List imageBytes, {int maxWidth = 2560, int quality = 92}) async {
    try {
      // Декодируем изображение
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        print('⚠️  Не удалось декодировать изображение, возвращаем оригинал');
        return imageBytes;
      }
      
      // Вычисляем новый размер с сохранением пропорций
      int newWidth = originalImage.width;
      int newHeight = originalImage.height;
      
      if (originalImage.width > maxWidth) {
        newHeight = (originalImage.height * maxWidth / originalImage.width).round();
        newWidth = maxWidth;
      }
      
      // Если изображение уже меньше maxWidth, не изменяем размер
      if (newWidth == originalImage.width && newHeight == originalImage.height) {
        // Просто перекодируем с качеством для уменьшения размера
        final compressedBytes = Uint8List.fromList(
          img.encodeJpg(originalImage, quality: quality)
        );
        
        final savedBytes = imageBytes.length - compressedBytes.length;
        if (savedBytes > 0) {
          print('📦 Сжатие (качество): ${imageBytes.length} → ${compressedBytes.length} байт (${(savedBytes / imageBytes.length * 100).toStringAsFixed(1)}% меньше)');
        }
        return compressedBytes;
      }
      
      // Изменяем размер
      final resizedImage = img.copyResize(
        originalImage,
        width: newWidth,
        height: newHeight,
      );
      
      // Кодируем обратно в JPEG с качеством
      final compressedBytes = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: quality)
      );
      
      final savedBytes = imageBytes.length - compressedBytes.length;
      final savedPercent = (savedBytes / imageBytes.length * 100).toStringAsFixed(1);
      print('📦 Сжатие изображения: ${imageBytes.length} → ${compressedBytes.length} байт ($savedPercent% меньше, ${originalImage.width}x${originalImage.height} → ${newWidth}x${newHeight})');
      
      return compressedBytes;
    } catch (e) {
      print('⚠️  Ошибка сжатия изображения: $e, возвращаем оригинал');
      return imageBytes; // Возвращаем оригинал при ошибке
    }
  }

  /// Скачивание изображения
  Future<void> _downloadImage(String imageUrl, String fileName) async {
    try {
      final url = Uri.parse(imageUrl);
      if (await canLaunchUrl(url)) {
        // Открываем изображение в браузере/приложении для просмотра
        // Пользователь может сохранить его через контекстное меню
        await launchUrl(url, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(kIsWeb 
                ? 'Изображение открыто в новой вкладке. Используйте "Сохранить как..." для скачивания.'
                : 'Изображение открыто для просмотра'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('Не удалось открыть URL');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка скачивания: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendMessage() async {
    print('🔍 _sendMessage called');
    if (!mounted) {
      print('⚠️ Widget not mounted, returning');
      return;
    }
    
    final text = _controller.text.trim();
    final hasImage = _selectedImagePath != null || _selectedImageBytes != null;
    
    print('🔍 Text: "$text", hasImage: $hasImage');
    
    if (text.isEmpty && !hasImage) {
      print('⚠️ Text is empty and no image, returning');
      return;
    }
    
    print('✅ Proceeding with message send');

    String? imageUrl;

    // Загружаем изображение, если выбрано
    if (hasImage) {
      setState(() => _isUploadingImage = true);
      try {
        Uint8List bytes;
        String fileName;
        
        Uint8List? originalBytes;
        
        if (kIsWeb) {
          // На веб используем bytes напрямую
          if (_selectedImageBytes != null) {
            originalBytes = _selectedImageBytes!;
            // ✅ Сжимаем изображение перед загрузкой (для отображения)
            bytes = await _compressImage(_selectedImageBytes!);
            fileName = _selectedImageName ?? 'image.jpg';
            // Очищаем оригинальные байты из памяти после загрузки
          } else {
            throw Exception('Изображение не выбрано');
          }
        } else {
          // На мобильных/десктоп читаем из файла
          if (_selectedImagePath != null) {
            final file = File(_selectedImagePath!);
            originalBytes = await file.readAsBytes();
            // ✅ Сжимаем изображение перед загрузкой (для отображения)
            bytes = await _compressImage(originalBytes);
            fileName = _selectedImagePath!.split('/').last;
          } else {
            throw Exception('Изображение не выбрано');
          }
        }
        
        // ✅ Загружаем и оригинал, и сжатое изображение
        imageUrl = await _messagesService.uploadImage(bytes, fileName, originalBytes: originalBytes);
        
        // ✅ Очищаем память после успешной загрузки
        if (mounted) {
          setState(() {
            _selectedImagePath = null;
            _selectedImageBytes = null;
            _selectedImageName = null;
          });
        }
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

    // ✅ Сохраняем replyToMessageId перед очисткой
    final replyToMessageId = _replyToMessage?.id;
    final replyToMessage = _replyToMessage;
    
    // ✅ Создаем временное сообщение для оптимистичного обновления UI
    final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = Message(
      id: tempMessageId,
      chatId: widget.chatId,
      userId: widget.userId,
      content: text,
      imageUrl: imageUrl,
      originalImageUrl: imageUrl, // Временно используем тот же URL
      messageType: imageUrl != null ? (text.isNotEmpty ? 'text_image' : 'image') : 'text',
      senderEmail: widget.userEmail,
      createdAt: DateTime.now().toIso8601String(),
      isRead: false,
      replyToMessageId: replyToMessageId,
      replyToMessage: replyToMessage,
    );
    
    // ✅ Добавляем сообщение оптимистично в список (без перезагрузки)
    // Сохраняем позицию скролла ДО добавления сообщения
    bool wasAtBottom = false;
    double? savedScrollPosition;
    if (mounted && _scrollController.hasClients) {
      final currentMaxScroll = _scrollController.position.maxScrollExtent;
      savedScrollPosition = _scrollController.position.pixels;
      if (currentMaxScroll > 0) {
        final threshold = 100.0; // Увеличиваем порог для более надежной проверки
        wasAtBottom = savedScrollPosition >= (currentMaxScroll - threshold);
      } else {
        wasAtBottom = true; // Если список пустой или очень маленький, считаем что внизу
      }
    } else {
      wasAtBottom = true; // Если контроллер не готов, считаем что внизу (не скроллим)
    }
    
    if (mounted) {
      print('🔍 Adding temp message to UI: id=$tempMessageId, content=$text');
      print('🔍 Current messages count before: ${_messages.length}');
      print('🔍 Was at bottom before adding: $wasAtBottom');
      print('🔍 Saved scroll position: $savedScrollPosition');
      setState(() {
        // ✅ Создаем новый список для гарантированного обновления UI
        final newMessages = List<Message>.from(_messages);
        newMessages.add(tempMessage); // Добавляем в конец, чтобы новые были снизу
        _messages = newMessages;
        // Очищаем поле ответа
        _replyToMessage = null;
      });
      print('✅ Temp message added to UI. New count: ${_messages.length}');
      print('✅ First message ID: ${_messages.isNotEmpty ? _messages[0].id : "none"}');
      
      // После добавления сообщения нужно скроллить вниз, чтобы остаться внизу
      // (setState может сбросить позицию, поэтому нужно явно скроллить)
      // Используем двойной addPostFrameCallback для гарантии, что ListView пересчитал размеры
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            final maxScroll = _scrollController.position.maxScrollExtent;
            if (maxScroll > 0) {
              // Если был внизу - просто jumpTo (мгновенно, без анимации) к новому maxScrollExtent
              // Если не был внизу - не скроллим, пользователь сам прокрутит
              if (wasAtBottom) {
                _scrollController.jumpTo(maxScroll);
                print('✅ Jumped to bottom (was at bottom, staying there). New maxScroll: $maxScroll');
              } else {
                print('✅ Was not at bottom, keeping current position');
              }
            }
          }
        });
      });
      
      // ✅ НЕ сохраняем временное сообщение в кэш сразу
      // Оно будет сохранено только после получения реального ответа от сервера
      // Это предотвращает перезагрузку списка сообщений
    }
    
    try {
      // ✅ Отправляем сообщение и получаем ответ от сервера
      print('🔍 Calling sendMessage service: chatId=${widget.chatId}, text="$text", imageUrl=$imageUrl, replyToMessageId=$replyToMessageId');
      final sentMessage = await _messagesService.sendMessage(
        widget.chatId, 
        text, 
        imageUrl: imageUrl,
        replyToMessageId: replyToMessageId,
      );
      print('🔍 sendMessage service returned: ${sentMessage != null ? "message with id=${sentMessage.id}" : "null"}');
      
      if (mounted) {
        _controller.clear();
        // ✅ Память уже очищена выше после загрузки изображения
        // Дополнительная очистка на случай, если изображения не было
        if (_selectedImagePath != null || _selectedImageBytes != null) {
          setState(() {
            _selectedImagePath = null;
            _selectedImageBytes = null;
            _selectedImageName = null;
          });
        }
        
        // ✅ Если получили сообщение от сервера, обновляем временное сообщение
        if (sentMessage != null) {
          print('✅ Received message from server: id=${sentMessage.id}, content=${sentMessage.content}');
          print('🔍 Looking for temp message with id: $tempMessageId');
          print('🔍 Current messages count: ${_messages.length}');
          print('🔍 Current message IDs: ${_messages.map((m) => m.id).toList()}');
          
          // ✅ Обновляем сразу, без WidgetsBinding, чтобы не потерять сообщение
          final tempIndex = _messages.indexWhere((m) => m.id == tempMessageId);
          print('🔍 Looking for temp message with id: $tempMessageId');
          print('🔍 Current messages count: ${_messages.length}');
          print('🔍 Current message IDs: ${_messages.map((m) => m.id).toList()}');
          print('🔍 Temp message found at index: $tempIndex');
          
          if (tempIndex != -1) {
            print('✅ Replacing temp message at index $tempIndex with real message ${sentMessage.id}');
            setState(() {
              // ✅ Создаем новый список для принудительного обновления UI
              final newMessages = List<Message>.from(_messages);
              newMessages[tempIndex] = sentMessage;
              
              // ✅ Удаляем все старые временные сообщения от этого пользователя (кроме только что замененного)
              newMessages.removeWhere((m) => 
                m.id.startsWith('temp_') && 
                m.userId == widget.userId.toString() &&
                m.id != tempMessageId // НЕ удаляем то, что только что заменили
              );
              
              _messages = newMessages;
            });
            print('✅ Message updated in UI (new list created). Total messages: ${_messages.length}');
            print('✅ Message IDs after update: ${_messages.map((m) => m.id).toList()}');
          } else {
            // Если временное сообщение не найдено, проверяем, нет ли уже такого сообщения
            final existingIndex = _messages.indexWhere((m) => m.id == sentMessage.id);
            if (existingIndex != -1) {
              print('⚠️ Message already exists at index $existingIndex');
              // Обновляем сообщение на текущей позиции, без перемещения
              setState(() {
                final newMessages = List<Message>.from(_messages);
                newMessages[existingIndex] = sentMessage;
                
                // Удаляем временные сообщения
                newMessages.removeWhere((m) => 
                  m.id.startsWith('temp_') && 
                  m.userId == widget.userId.toString()
                );
                
                _messages = newMessages;
              });
              print('✅ Message updated in place at index $existingIndex');
            } else {
              print('⚠️ Temp message not found and message not in list, adding it');
              setState(() {
                // ✅ Создаем новый список для принудительного обновления UI
                final newMessages = List<Message>.from(_messages);
                newMessages.add(sentMessage); // добавляем в конец, новые снизу
                
                // ✅ Удаляем все старые временные сообщения от этого пользователя
                newMessages.removeWhere((m) => 
                  m.id.startsWith('temp_') && 
                  m.userId == widget.userId.toString()
                );
                
                _messages = newMessages;
              });
              print('✅ Message added to end. Total: ${_messages.length} (new list created)');
            }
          }
          
          // ✅ После обновления сообщения от сервера нужно сохранить позицию внизу
          // (setState может сбросить позицию, поэтому нужно явно скроллить)
          // Используем двойной addPostFrameCallback для гарантии, что ListView пересчитал размеры
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scrollController.hasClients) {
                final maxScroll = _scrollController.position.maxScrollExtent;
                if (maxScroll > 0) {
                  // Если был внизу до отправки - остаемся внизу (jumpTo без анимации)
                  // Используем wasAtBottom из области видимости выше
                  if (wasAtBottom) {
                    _scrollController.jumpTo(maxScroll);
                    print('✅ Jumped to bottom after message update (was at bottom)');
                  } else {
                    // Если не был внизу - не скроллим, пользователь сам прокрутит
                    print('✅ Was not at bottom, keeping current position');
                  }
                }
              }
            });
          });
          
          // Принудительные обновления UI больше не нужны — список обновляется напрямую
          
          // ✅ Сохраняем в кэш с задержкой, чтобы не триггерить перезагрузку
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) {
              LocalMessagesService.addMessage(widget.chatId, sentMessage);
            }
          });
        } else {
          print('⚠️ No message received from server response');
        }
        
        // ✅ Fallback: Если через 3 секунды временное сообщение все еще есть,
        // значит WebSocket не получил сообщение - оставляем как есть
        // (сообщение уже обновлено из ответа сервера выше)
        Future.delayed(Duration(seconds: 3), () {
          if (mounted && _messages.any((m) => m.id == tempMessageId)) {
            print('⚠️ Temp message still exists after 3s, but should be replaced by WebSocket or server response');
          }
        });
      }
      
      // ✅ Сообщение уже обновлено из ответа сервера
      // Также будет обновлено через WebSocket (если придет) для синхронизации с другими клиентами
      
    } catch (e, stackTrace) {
      print('❌ Error sending message: $e');
      print('❌ Stack trace: $stackTrace');
      
      // ✅ Удаляем временное сообщение при ошибке
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == tempMessageId);
        });
        
        // Восстанавливаем поле ответа, если была ошибка
        if (_replyToMessage == null && tempMessage.replyToMessage != null) {
          setState(() {
            _replyToMessage = tempMessage.replyToMessage;
          });
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки сообщения: $e')),
        );
      }
    }
  }

  // ✅ Меню действий с сообщением
  Future<void> _showMessageMenu(Message message, {bool isMine = true}) async {
    if (!mounted) return;
    
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.reply),
              title: Text('Ответить'),
              onTap: () => Navigator.pop(context, 'reply'),
            ),
            ListTile(
              leading: Icon(Icons.forward),
              title: Text('Переслать'),
              onTap: () => Navigator.pop(context, 'forward'),
            ),
            // ✅ Редактировать можно только свои текстовые сообщения
            if (isMine && message.hasText && !message.hasImage)
              ListTile(
                leading: Icon(Icons.edit),
                title: Text('Редактировать'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            ListTile(
              leading: Icon(message.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(message.isPinned ? 'Открепить' : 'Закрепить'),
              onTap: () => Navigator.pop(context, message.isPinned ? 'unpin' : 'pin'),
            ),
            ListTile(
              leading: Icon(Icons.emoji_emotions),
              title: Text('Реакция'),
              onTap: () => Navigator.pop(context, 'reaction'),
            ),
            // ✅ Удалить можно только свои сообщения
            if (isMine)
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Удалить', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ListTile(
              leading: Icon(Icons.close),
              title: Text('Отмена'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    
    if (action == 'reply') {
      setState(() {
        _replyToMessage = message;
      });
    } else if (action == 'forward') {
      _showForwardDialog(message);
    } else if (action == 'edit') {
      _showEditMessageDialog(message);
    } else if (action == 'pin') {
      _pinMessage(message);
    } else if (action == 'unpin') {
      _unpinMessage(message);
    } else if (action == 'reaction') {
      _showReactionPicker(message);
    } else if (action == 'delete') {
      _showDeleteMessageDialog(message);
    }
  }
  
  // ✅ Диалог пересылки сообщения
  Future<void> _showForwardDialog(Message message) async {
    if (!mounted) return;
    
    // Загружаем список чатов пользователя
    final chats = await _chatsService.fetchChats(widget.userId);
    final availableChats = chats.where((chat) => chat.id != widget.chatId).toList();
    
    if (availableChats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Нет других чатов для пересылки')),
      );
      return;
    }
    
    // Состояние выбранных чатов
    final selectedChatIds = <String>{};
    
    final selectedChats = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Переслать сообщение'),
              content: Container(
                width: double.maxFinite,
                constraints: BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableChats.length,
                  itemBuilder: (context, index) {
                    final chat = availableChats[index];
                    final isSelected = selectedChatIds.contains(chat.id);
                    return CheckboxListTile(
                      title: Text(chat.name),
                      value: isSelected,
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selectedChatIds.add(chat.id);
                          } else {
                            selectedChatIds.remove(chat.id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: selectedChatIds.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context, selectedChatIds.toList());
                        },
                  child: Text('Переслать'),
                ),
              ],
            );
          },
        );
      },
    );
    
    if (selectedChats != null && selectedChats.isNotEmpty) {
      try {
        await _messagesService.forwardMessage(message.id, selectedChats);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Сообщение переслано в ${selectedChats.length} чат(ов)')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка пересылки: $e')),
          );
        }
      }
    }
  }
  
  // ✅ Закрепить сообщение
  Future<void> _pinMessage(Message message) async {
    try {
      await _messagesService.pinMessage(message.id);
      if (mounted) {
        await _loadPinnedMessages();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сообщение закреплено')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка закрепления: $e')),
        );
      }
    }
  }
  
  // ✅ Открепить сообщение
  Future<void> _unpinMessage(Message message) async {
    try {
      await _messagesService.unpinMessage(message.id);
      if (mounted) {
        await _loadPinnedMessages();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сообщение откреплено')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка открепления: $e')),
        );
      }
    }
  }
  
  // ✅ Показать выбор реакции
  Future<void> _showReactionPicker(Message message) async {
    if (!mounted) return;
    
    final reaction = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Container(
          padding: EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              _buildReactionButton('👍', context),
              _buildReactionButton('❤️', context),
              _buildReactionButton('😂', context),
              _buildReactionButton('😮', context),
              _buildReactionButton('😢', context),
              _buildReactionButton('🙏', context),
              _buildReactionButton('🔥', context),
              _buildReactionButton('⭐', context),
            ],
          ),
        ),
      ),
    );
    
    if (reaction != null) {
      try {
        // Проверяем, есть ли уже такая реакция
        final hasReaction = message.reactions?.any((r) => r.reaction == reaction) ?? false;
        if (hasReaction) {
          await _messagesService.removeReaction(message.id, reaction);
        } else {
          await _messagesService.addReaction(message.id, reaction);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      }
    }
  }
  
  Widget _buildReactionButton(String emoji, BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, emoji),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Text(
            emoji,
            style: TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }

  // ✅ Диалог редактирования сообщения
  Future<void> _showEditMessageDialog(Message message) async {
    if (!mounted) return;
    
    final textController = TextEditingController(text: message.content);
    
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Редактировать сообщение'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Введите текст сообщения',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final newContent = textController.text.trim();
              if (newContent.isNotEmpty) {
                Navigator.pop(context, {'content': newContent});
              }
            },
            child: Text('Сохранить'),
          ),
        ],
      ),
    );
    
    if (result != null && result['content'] != null) {
      try {
        await _messagesService.editMessage(message.id, content: result['content']!);
        if (mounted) {
          setState(() {
            final index = _messages.indexWhere((m) => m.id == message.id);
            if (index != -1) {
              _messages[index] = Message(
                id: message.id,
                chatId: message.chatId,
                userId: message.userId,
                content: result['content']!,
                imageUrl: message.imageUrl,
                originalImageUrl: message.originalImageUrl,
                messageType: message.messageType,
                senderEmail: message.senderEmail,
                createdAt: message.createdAt,
                deliveredAt: message.deliveredAt,
                editedAt: DateTime.now().toIso8601String(),
                isRead: message.isRead,
                readAt: message.readAt,
              );
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка редактирования сообщения: $e')),
          );
        }
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

  // ✅ Выход из чата
  Future<void> _leaveChat() async {
    if (!mounted) return;

    // Показываем диалог подтверждения
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Выйти из чата?'),
        content: Text('Вы уверены, что хотите выйти из чата "${widget.chatName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _chatsService.leaveChat(widget.chatId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Вы вышли из чата'),
            duration: const Duration(seconds: 2),
          ),
        );
        // Возвращаемся на предыдущий экран
        Navigator.pop(context);
      }
    } catch (e) {
      print('Ошибка выхода из чата: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при выходе из чата: ${e.toString().replaceFirst('Exception: ', '')}'),
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

  // ✅ Вычисляем высоту блока закрепленных сообщений
  double _getPinnedMessagesHeight() {
    if (_pinnedMessages.isEmpty) return 0.0;
    // Компактные размеры
    final headerHeight = 28.0; // Компактный заголовок
    final messageHeight = 32.0; // Компактная высота одного сообщения
    final messagesCount = _pinnedMessages.length > 3 ? 3 : _pinnedMessages.length;
    final padding = 12.0; // Внутренние отступы
    final margin = 8.0; // Внешние отступы
    return headerHeight + (messagesCount * messageHeight) + padding + margin;
  }

  @override
  Widget build(BuildContext context) {
    final pinnedHeight = _getPinnedMessagesHeight();
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.grey.shade800),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.chatName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade900,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.userEmail,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _accent1.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.people_rounded, color: _accent1),
              onPressed: _showMembersDialog,
              tooltip: 'Участники чата',
            ),
          ),
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_accent1, _accent2]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _accent1.withOpacity(0.25),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(Icons.person_add_rounded, color: Colors.white),
              onPressed: _showAddMembersDialog,
              tooltip: 'Добавить участников',
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'clear') _clearChat();
              if (value == 'leave') _leaveChat();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_rounded, color: Colors.red.shade400, size: 20),
                    SizedBox(width: 10),
                    Text('Очистить чат'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app_rounded, color: Colors.orange.shade700, size: 20),
                    SizedBox(width: 10),
                    Text('Выйти из чата'),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_accent1),
                      strokeWidth: 3,
                    ),
                  )
                : RepaintBoundary(
                  child: Stack(
                    children: [
                      // Отступ сверху для закрепленных сообщений
                      Padding(
                        padding: EdgeInsets.only(
                          top: pinnedHeight,
                        ),
                        child: ListView.builder(
                          key: ValueKey('messages_list_${widget.chatId}'),
                          controller: _scrollController,
                          reverse: false, // старые сверху, новые снизу
                          itemCount: _messages.length +
                              (_hasMoreMessages && !_isLoadingMore && _messages.isNotEmpty ? 1 : 0) + // кнопка
                              (_isLoadingMore ? 1 : 0), // индикатор
                        itemBuilder: (context, index) {
                          int cursor = 0;

                          // Кнопка "Загрузить старые"
                          if (_hasMoreMessages && !_isLoadingMore && _messages.isNotEmpty) {
                            if (index == cursor) {
                              return Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: OutlinedButton.icon(
                                    onPressed: _loadMoreMessages,
                                    icon: Icon(Icons.arrow_upward, size: 18),
                                    label: Text('Загрузить старые сообщения'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _accent1,
                                      side: BorderSide(color: _accent1.withOpacity(0.35), width: 1.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            cursor++;
                          }

                          // Индикатор подгрузки
                          if (_isLoadingMore) {
                            if (index == cursor) {
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
                            cursor++;
                          }

                          // Сообщения
                          final msgIndex = index - cursor;
                          if (msgIndex < 0 || msgIndex >= _messages.length) {
                            return SizedBox.shrink();
                          }
                          final msg = _messages[msgIndex];
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
                                _accent3,
                                _accent2,
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
                          onLongPress: () => _showMessageMenu(msg, isMine: isMine),
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
                                        _accent1,
                                        _accent2,
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
                                          ? _accent1
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
                                // ✅ Показываем иконку закрепления
                                if (msg.isPinned) ...[
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.push_pin,
                                        size: 14,
                                        color: isMine ? Colors.white70 : Colors.amber.shade700,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Закреплено',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: isMine ? Colors.white70 : Colors.amber.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                ],
                                // ✅ Отображение ответа на сообщение (если есть)
                                if (msg.replyToMessage != null) ...[
                                  Container(
                                    margin: EdgeInsets.only(bottom: 8),
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isMine 
                                          ? Colors.white.withOpacity(0.2)
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                          color: isMine ? Colors.white : _accent1,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          msg.replyToMessage!.senderEmail,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isMine 
                                                ? Colors.white.withOpacity(0.9)
                                                : _accent1,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        if (msg.replyToMessage!.hasImage)
                                          Row(
                                            children: [
                                              Icon(Icons.image, size: 14, color: isMine ? Colors.white70 : Colors.grey.shade600),
                                              SizedBox(width: 4),
                                              Text(
                                                'Фото',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isMine ? Colors.white70 : Colors.grey.shade600,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          Text(
                                            msg.replyToMessage!.content.length > 50
                                                ? '${msg.replyToMessage!.content.substring(0, 50)}...'
                                                : msg.replyToMessage!.content,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isMine ? Colors.white70 : Colors.grey.shade700,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                                // Показываем отправителя только если это не ваше сообщение
                                if (!isMine) ...[
                                  Text(
                                    msg.senderEmail,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isMine ? Colors.white70 : _accent1,
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
                                                  child: ConstrainedBox(
                                                    constraints: BoxConstraints(
                                                      maxWidth: MediaQuery.of(context).size.width,
                                                      maxHeight: MediaQuery.of(context).size.height,
                                                    ),
                                                    child: Image.network(
                                                      msg.imageUrl!,
                                                      fit: BoxFit.contain, // ✅ Сохраняем пропорции
                                                      // Убираем cacheWidth и cacheHeight для полноэкранного просмотра, чтобы сохранить пропорции
                                                      // Или используем только cacheWidth для экономии памяти
                                                      cacheWidth: 1920,  // ✅ Декодируем максимум 1920px ширины (пропорции сохранятся)
                                                      // cacheHeight не задаем, чтобы сохранить пропорции изображения
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
                                              ),
                                              Positioned(
                                                top: 40,
                                                right: 20,
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    // ✅ Кнопка скачивания оригинала (если есть)
                                                    if (msg.hasOriginalImage || msg.imageUrl != null)
                                                      IconButton(
                                                        icon: Icon(Icons.download, color: Colors.white),
                                                        onPressed: () => _downloadImage(
                                                          msg.originalImageUrl ?? msg.imageUrl!,
                                                          msg.imageUrl?.split('/').last ?? 'image.jpg'
                                                        ),
                                                        style: IconButton.styleFrom(
                                                          backgroundColor: Colors.black54,
                                                        ),
                                                      ),
                                                    SizedBox(width: 8),
                                                    IconButton(
                                                      icon: Icon(Icons.close, color: Colors.white),
                                                      onPressed: () => Navigator.pop(context),
                                                      style: IconButton.styleFrom(
                                                        backgroundColor: Colors.black54,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: 250, // Максимальная ширина
                                          maxHeight: 400, // Максимальная высота (больше для вертикальных изображений)
                                        ),
                                        child: Image.network(
                                          msg.imageUrl!,
                                          fit: BoxFit.contain, // ✅ Сохраняем пропорции изображения
                                          cacheWidth: 500,  // ✅ Декодируем максимум 500px ширины (экономия памяти)
                                          // cacheHeight не задаем, чтобы сохранить пропорции
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
                                // ✅ Отображение реакций
                                if (msg.reactions != null && msg.reactions!.isNotEmpty) ...[
                                  SizedBox(height: 4),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: msg.reactions!.map((reaction) {
                                      return GestureDetector(
                                        onTap: () => _showReactionPicker(msg),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isMine 
                                                ? Colors.white.withOpacity(0.2)
                                                : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                reaction.reaction,
                                                style: TextStyle(fontSize: 14),
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                '1', // TODO: Подсчитывать количество одинаковых реакций
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isMine ? Colors.white70 : Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                                SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatDate(msg.createdAt),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isMine
                                            ? Colors.white.withOpacity(0.8)
                                            : Colors.grey.shade500,
                                      ),
                                    ),
                                    // ✅ Отображаем статус сообщения только для своих сообщений
                                    if (isMine) ...[
                                      SizedBox(width: 4),
                                      _buildMessageStatus(msg),
                                    ],
                                    // ✅ Показываем метку "Отредактировано", если сообщение было отредактировано
                                    if (msg.isEdited) ...[
                                      SizedBox(width: 4),
                                      Text(
                                        'отредактировано',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic,
                                          color: isMine
                                              ? Colors.white.withOpacity(0.6)
                                              : Colors.grey.shade400,
                                        ),
                                      ),
                                    ],
                                  ],
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
                      // ✅ Закрепленные сообщения - всегда видны вверху
                      if (_pinnedMessages.isNotEmpty)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.97),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _accent1.withOpacity(0.18),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Компактный заголовок
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.push_pin,
                                        size: 12,
                                        color: _accent1.withOpacity(0.8),
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Закреплено',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _accent1.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${_pinnedMessages.length}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 10,
                                            color: _accent1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Компактный список сообщений
                                Padding(
                                  padding: EdgeInsets.only(left: 8, right: 8, bottom: 6),
                                  child: Column(
                                    children: _pinnedMessages.take(3).toList().asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final pinned = entry.value;
                                      final isLast = index == (_pinnedMessages.length > 3 ? 2 : _pinnedMessages.length - 1);
                                      
                                      return Container(
                                        margin: EdgeInsets.only(bottom: isLast ? 0 : 4),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () {
                                              final messageIndex = _messages.indexWhere((m) => m.id == pinned.id);
                                              if (messageIndex != -1 && _scrollController.hasClients) {
                                                final targetPosition = (messageIndex * 100.0) + pinnedHeight;
                                                _scrollController.animateTo(
                                                  targetPosition,
                                                  duration: Duration(milliseconds: 300),
                                                  curve: Curves.easeInOut,
                                                );
                                              }
                                            },
                                            borderRadius: BorderRadius.circular(6),
                                            child: Container(
                                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.grey.shade200,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.push_pin,
                                                    size: 12,
                                                    color: _accent1.withOpacity(0.6),
                                                  ),
                                                  SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      pinned.content.isNotEmpty 
                                                          ? (pinned.content.length > 40 
                                                              ? '${pinned.content.substring(0, 40)}...'
                                                              : pinned.content)
                                                          : 'Фото',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w400,
                                                        color: Colors.grey.shade700,
                                                        height: 1.2,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  SizedBox(width: 6),
                                                  Icon(
                                                    Icons.chevron_right,
                                                    size: 16,
                                                    color: Colors.grey.shade400,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
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
                    // ✅ Превью ответа на сообщение
                    if (_replyToMessage != null)
                      Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _accent1.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              color: _accent1,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ответ на сообщение',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _accent1,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  if (_replyToMessage!.hasImage)
                                    Row(
                                      children: [
                                        Icon(Icons.image, size: 14, color: Colors.grey.shade600),
                                        SizedBox(width: 4),
                                        Text(
                                          'Фото',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      _replyToMessage!.content.length > 50
                                          ? '${_replyToMessage!.content.substring(0, 50)}...'
                                          : _replyToMessage!.content,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, size: 18),
                              onPressed: () {
                                setState(() {
                                  _replyToMessage = null;
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
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
                        Container(
                          decoration: BoxDecoration(
                            color: _accent1.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            icon: Icon(Icons.image_rounded, color: _accent1),
                            onPressed: _pickImage,
                            tooltip: 'Прикрепить изображение',
                          ),
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.grey.shade200),
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
                                  _accent1,
                                  _accent2,
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _accent1.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(Icons.send, color: Colors.white),
                              onPressed: () {
                                print('🔍 Send button pressed!');
                                _sendMessage();
                              },
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
