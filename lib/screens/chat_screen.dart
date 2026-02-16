import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/message.dart';
import '../services/messages_service.dart';
import '../services/chats_service.dart';
import '../services/storage_service.dart';
import '../services/local_messages_service.dart'; // ✅ Импорт сервиса кэширования
import '../services/notification_feedback_service.dart';
import 'add_members_dialog.dart';
import 'chat_members_dialog.dart';

/// Элементы списка сообщений: кнопка «ещё», индикатор загрузки, заголовок даты или сообщение
class _ListEntry {}
class _LoadMoreEntry extends _ListEntry {}
class _LoadingEntry extends _ListEntry {}
class _DateHeaderEntry extends _ListEntry { final String label; _DateHeaderEntry(this.label); }
class _MessageEntry extends _ListEntry { final int index; _MessageEntry(this.index); }

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String chatId;
  final String chatName;
  final bool isGroup;

  const ChatScreen({
    required this.userId,
    required this.userEmail,
    required this.chatId,
    required this.chatName,
    required this.isGroup,
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
  final Map<String, GlobalKey> _messageKeys = {};

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
  String? _selectedFilePath;
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  int? _selectedFileSize;
  bool _isUploadingFile = false;
  Message? _replyToMessage; // ✅ Сообщение, на которое отвечаем
  List<Message> _pinnedMessages = []; // ✅ Закрепленные сообщения
  String? _highlightMessageId; // ✅ Подсветка сообщения при прыжке

  // ✅ Voice messages (recording + playback)
  final AudioRecorder _voiceRecorder = AudioRecorder();
  bool _isRecordingVoice = false;
  Duration _voiceRecordDuration = Duration.zero;
  Timer? _voiceRecordTimer;
  String? _voiceRecordTempPath;

  final AudioPlayer _voicePlayer = AudioPlayer();
  String? _voicePlayingMessageId;
  Duration _voicePosition = Duration.zero;
  Duration? _voiceDuration;
  bool _voiceIsPlaying = false;
  ProcessingState _voiceProcessingState = ProcessingState.idle;
  StreamSubscription<Duration>? _voicePositionSub;
  StreamSubscription<Duration?>? _voiceDurationSub;
  StreamSubscription<PlayerState>? _voicePlayerStateSub;

  // ✅ Drag-and-drop файлов (десктоп/веб)
  bool _isDraggingFile = false;

  // ✅ Realtime presence/typing
  final Map<String, String> _memberEmailById = {};
  final Set<String> _onlineUserIds = <String>{};
  final Map<String, DateTime> _typingUntilByUserId = <String, DateTime>{};
  Timer? _typingStopTimer;
  Timer? _typingCleanupTimer;
  bool _sentTyping = false;
  bool _subscribedToChatRealtime = false;
  late String _chatTitle;

  List<_ListEntry>? _cachedListEntries;
  int _listEntriesCacheKey = -1;

  List<_ListEntry> get _listEntries {
    final len = _messages.length;
    final key = len ^ (_hasMoreMessages ? 0x10000 : 0) ^ (_isLoadingMore ? 0x20000 : 0) ^
        (len > 0 ? _messages.first.id.hashCode : 0) ^
        (len > 0 ? _messages.last.id.hashCode : 0);
    if (_cachedListEntries != null && _listEntriesCacheKey == key) {
      return _cachedListEntries!;
    }
    _listEntriesCacheKey = key;
    final list = <_ListEntry>[];
    if (_hasMoreMessages && !_isLoadingMore && _messages.isNotEmpty) list.add(_LoadMoreEntry());
    if (_isLoadingMore) list.add(_LoadingEntry());
    String? lastDateKey;
    for (int i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      final dt = DateTime.tryParse(msg.createdAt)?.toLocal();
      if (dt != null) {
        final key = '${dt.year}-${dt.month}-${dt.day}';
        if (key != lastDateKey) {
          lastDateKey = key;
          final label = _formatDateHeader(dt);
          list.add(_DateHeaderEntry(label));
        }
      }
      list.add(_MessageEntry(i));
    }
    _cachedListEntries = list;
    return list;
  }

  static String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Сегодня';
    if (d == yesterday) return 'Вчера';
    return DateFormat('d MMMM', 'ru').format(dt);
  }

  Widget _buildDateHeader(String label) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _accent1.withValues(alpha:0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _accent1.withValues(alpha:0.95),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showInviteDialog() async {
    if (!mounted) return;
    bool isLoading = false;
    String? error;
    Map<String, dynamic>? invite;
    final ttlController = TextEditingController(text: '1440'); // 1 день
    final usesController = TextEditingController(text: '10');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> create() async {
              setLocal(() {
                isLoading = true;
                error = null;
              });
              try {
                final ttl = int.tryParse(ttlController.text.trim());
                final max = int.tryParse(usesController.text.trim());
                final res = await _chatsService.createInvite(
                  widget.chatId,
                  ttlMinutes: ttl,
                  maxUses: max,
                );
                setLocal(() {
                  invite = res;
                  isLoading = false;
                });
              } catch (e) {
                setLocal(() {
                  isLoading = false;
                  error = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            final code = invite?['code']?.toString();

            return AlertDialog(
              title: Text('Пригласить в чат'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (code != null && code.isNotEmpty) ...[
                    Text('Код:'),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            code,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy_rounded),
                          tooltip: 'Скопировать',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Код скопирован')),
                            );
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Передайте этот код человеку — он введёт его в “Вступить по коду”.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ] else ...[
                    Text(
                      'Создайте код приглашения. Его можно ограничить по времени и числу использований.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: ttlController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'TTL (минуты)',
                        helperText: 'Напр. 60 = 1 час, 1440 = 1 день',
                      ),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: usesController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Макс. использований',
                        helperText: 'Напр. 1 или 10',
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    SizedBox(height: 10),
                    Text(error!, style: TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                  child: Text('Закрыть'),
                ),
                if (code == null || code.isEmpty)
                  ElevatedButton(
                    onPressed: isLoading ? null : create,
                    child: isLoading
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Создать код'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _renameGroupChatDialog() async {
    if (!mounted) return;
    final controller = TextEditingController(text: _chatTitle);
    bool isLoading = false;
    String? error;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> save() async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                setLocal(() => error = 'Введите имя');
                return;
              }
              setLocal(() {
                isLoading = true;
                error = null;
              });
              try {
                final updated = await _chatsService.renameChat(widget.chatId, name);
                final newName = (updated['name'] ?? name).toString();
                if (!mounted) return;
                setState(() => _chatTitle = newName);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Название обновлено')),
                );
              } catch (e) {
                setLocal(() {
                  isLoading = false;
                  error = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              title: Text('Переименовать чат'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Название группы',
                      errorText: error,
                    ),
                    onSubmitted: (_) => save(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                  child: Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : save,
                  child: isLoading
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _chatTitle = widget.chatName;

    // ✅ Voice player streams (single player for whole chat)
    _voicePositionSub = _voicePlayer.positionStream.listen((pos) {
      if (!mounted) return;
      if (_voicePlayingMessageId == null) return;
      setState(() => _voicePosition = pos);
    });
    _voiceDurationSub = _voicePlayer.durationStream.listen((dur) {
      if (!mounted) return;
      if (_voicePlayingMessageId == null) return;
      setState(() => _voiceDuration = dur);
    });
    _voicePlayerStateSub = _voicePlayer.playerStateStream.listen((st) {
      if (!mounted) return;
      setState(() {
        _voiceIsPlaying = st.playing;
        _voiceProcessingState = st.processingState;
        if (st.processingState == ProcessingState.completed) {
          _voicePosition = Duration.zero;
        }
      });
      if (st.processingState == ProcessingState.completed) {
        _voicePlayer.seek(Duration.zero);
        _voicePlayer.pause();
      }
    });

    // Инициализируем WebSocket асинхронно
    _initWebSocket();
    
    _loadMessages();
    _loadPinnedMessages(); // ✅ Загружаем закрепленные сообщения
    _loadChatMembers(); // ✅ Для presence/typing отображения
    
    // ✅ Отмечаем все сообщения как прочитанные при открытии чата
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markChatAsRead();
    });
  }

  Future<void> _loadChatMembers() async {
    try {
      final members = await _chatsService.getChatMembers(widget.chatId);
      if (!mounted) return;
      setState(() {
        _memberEmailById
          ..clear()
          ..addEntries(members.map((m) {
            final id = (m['id'] ?? '').toString();
            final email = (m['email'] ?? '').toString();
            return MapEntry(id, email);
          }).where((e) => e.key.isNotEmpty));
      });
    } catch (e) {
      // Не критично — presence/typing просто будет без имён
      if (kDebugMode) print('Ошибка загрузки участников (для presence/typing): $e');
    }
  }

  GlobalKey _keyForMessage(String id) {
    return _messageKeys.putIfAbsent(id, () => GlobalKey());
  }

  Future<void> _scrollToMessage(String messageId) async {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: 0.3,
    );
  }

  Future<void> _jumpToMessage(String messageId) async {
    try {
      final around = await _messagesService.fetchMessagesAround(widget.chatId, messageId, limit: 50);
      if (!mounted) return;

      // Сохраняем временные сообщения (если есть), чтобы не потерять офлайн/отправленные
      final temp = _messages.where((m) => m.id.startsWith('temp_')).toList();
      final aroundIds = around.map((m) => m.id).toSet();
      final uniqueTemp = temp.where((m) => !aroundIds.contains(m.id)).toList();

      final minId = around
          .map((m) => int.tryParse(m.id) ?? 1 << 30)
          .fold<int>(1 << 30, (a, b) => a < b ? a : b);

      setState(() {
        _messages = [...around, ...uniqueTemp];
        _messages.sort((a, b) {
          try {
            return DateTime.parse(a.createdAt).compareTo(DateTime.parse(b.createdAt));
          } catch (_) {
            return 0;
          }
        });
        _oldestMessageId = (minId == (1 << 30)) ? null : minId.toString();
        _hasMoreMessages = true;
        _highlightMessageId = messageId;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _scrollToMessage(messageId);
      });

      Future.delayed(Duration(seconds: 2), () {
        if (!mounted) return;
        if (_highlightMessageId == messageId) {
          setState(() => _highlightMessageId = null);
        }
      });
    } catch (e) {
      if (kDebugMode) print('Ошибка перехода к сообщению: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось перейти к сообщению')),
      );
    }
  }

  Future<void> _openSearch() async {
    final controller = TextEditingController();
    Timer? debounce;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        List<Map<String, dynamic>> results = [];
        bool isLoading = false;
        String? error;

        Future<void> runSearch(StateSetter setModalState, String q) async {
          final query = q.trim().toLowerCase();
          if (query.isEmpty) {
            setModalState(() {
              results = [];
              error = null;
              isLoading = false;
            });
            return;
          }
          setModalState(() {
            isLoading = true;
            error = null;
          });
          try {
            final found = await _messagesService.searchMessages(widget.chatId, q.trim(), limit: 30);
            setModalState(() {
              results = found;
              isLoading = false;
            });
          } catch (e) {
            // Локальный поиск по уже загруженным сообщениям (офлайн / при ошибке API)
            final local = _messages.where((m) {
              final content = (m.content).toLowerCase();
              final fileName = (m.fileName ?? '').toLowerCase();
              return content.contains(query) || fileName.contains(query);
            }).take(30).map((m) => {
              'message_id': m.id,
              'sender_email': m.senderEmail,
              'content_snippet': m.content.length > 80 ? '${m.content.substring(0, 80)}…' : m.content,
              'created_at': m.createdAt,
            }).toList();
            setModalState(() {
              results = local;
              isLoading = false;
              error = local.isEmpty ? 'Ничего не найдено' : null;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Поиск по сообщениям…',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onChanged: (v) {
                            debounce?.cancel();
                            debounce = Timer(Duration(milliseconds: 250), () {
                              runSearch(setModalState, v);
                            });
                          },
                        ),
                      ),
                      if (isLoading)
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (error != null)
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(error!, style: TextStyle(color: Colors.red)),
                        ),
                      Flexible(
                        child: results.isEmpty
                            ? Padding(
                                padding: EdgeInsets.fromLTRB(16, 10, 16, 20),
                                child: Text(
                                  controller.text.trim().isEmpty
                                      ? 'Введите запрос для поиска'
                                      : 'Ничего не найдено',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: results.length,
                                separatorBuilder: (_, __) => Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final r = results[index];
                                  final messageId = (r['message_id'] ?? '').toString();
                                  final sender = (r['sender_email'] ?? '').toString();
                                  final snippet = (r['content_snippet'] ?? '').toString();
                                  final createdAt = (r['created_at'] ?? '').toString();
                                  return ListTile(
                                    title: Text(
                                      sender.isNotEmpty ? sender : 'Сообщение',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      snippet,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Text(
                                      createdAt.isNotEmpty ? _formatDate(createdAt) : '',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      _jumpToMessage(messageId);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    debounce?.cancel();
    controller.dispose();
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
      if (kDebugMode) print('Ошибка загрузки закрепленных сообщений: $e');
    }
  }
  
  // ✅ Отметить все сообщения в чате как прочитанные
  Future<void> _markChatAsRead() async {
    try {
      await _messagesService.markChatAsRead(widget.chatId);
    } catch (e) {
      if (kDebugMode) print('Ошибка отметки чата как прочитанного: $e');
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
          if (kDebugMode) print('WebSocket received: $event');
          final data = jsonDecode(event);
          if (kDebugMode) print('Parsed WebSocket data: $data');
          
          // Проверяем тип сообщения
          final messageType = data['type'];

          // ✅ Presence: начальное состояние
          if (messageType == 'presence_state') {
            final chatId = data['chat_id']?.toString();
            if (chatId == widget.chatId.toString() && mounted) {
              final list = (data['online_user_ids'] as List<dynamic>? ?? []);
              setState(() {
                _onlineUserIds
                  ..clear()
                  ..addAll(list.map((e) => e.toString()));
              });
            }
            return;
          }

          // ✅ Presence: online/offline события
          if (messageType == 'presence') {
            final chatId = data['chat_id']?.toString();
            if (chatId == widget.chatId.toString() && mounted) {
              final uid = data['user_id']?.toString();
              final status = data['status']?.toString();
              if (uid != null && uid.isNotEmpty) {
                setState(() {
                  if (status == 'online') {
                    _onlineUserIds.add(uid);
                  } else if (status == 'offline') {
                    _onlineUserIds.remove(uid);
                    _typingUntilByUserId.remove(uid);
                  }
                });
              }
            }
            return;
          }

          // ✅ Typing indicator
          if (messageType == 'typing') {
            final chatId = data['chat_id']?.toString();
            final uid = data['user_id']?.toString();
            final isTyping = data['is_typing'] == true;
            if (chatId == widget.chatId.toString() && uid != null && uid.isNotEmpty && uid != widget.userId.toString() && mounted) {
              setState(() {
                if (isTyping) {
                  _typingUntilByUserId[uid] = DateTime.now().add(Duration(seconds: 5));
                } else {
                  _typingUntilByUserId.remove(uid);
                }
              });
              _scheduleTypingCleanup();
            }
            return;
          }
          
          if (messageType == 'message_deleted') {
            // Обработка уведомления об удалении сообщения
            final deletedMessageId = data['message_id']?.toString();
            final chatId = data['chat_id']?.toString();
            final currentChatId = widget.chatId.toString();
            
            if (chatId == currentChatId && deletedMessageId != null) {
              if (kDebugMode) print('Message deleted notification: $deletedMessageId');
              if (mounted) {
                setState(() {
                  _messages.removeWhere((m) => m.id.toString() == deletedMessageId);
                  if (kDebugMode) print('Message removed from list. Remaining messages: ${_messages.length}');
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
                    fileUrl: msg.fileUrl,
                    fileName: msg.fileName,
                    fileSize: msg.fileSize,
                    fileMime: msg.fileMime,
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
                      fileUrl: msg.fileUrl,
                      fileName: msg.fileName,
                      fileSize: msg.fileSize,
                      fileMime: msg.fileMime,
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
                    fileUrl: data['file_url'] ?? msg.fileUrl,
                    fileName: data['file_name'] ?? msg.fileName,
                    fileSize: data['file_size'] ?? msg.fileSize,
                    fileMime: data['file_mime'] as String? ?? msg.fileMime,
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
                    fileUrl: msg.fileUrl,
                    fileName: msg.fileName,
                    fileSize: msg.fileSize,
                    fileMime: msg.fileMime,
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
          
          if (kDebugMode) print('WebSocket chat_id: $chatId, current chat_id: $currentChatId');
          
          if (chatId == currentChatId) {
            if (kDebugMode) print('Message is for current chat');
            try {
              final message = Message.fromJson(data);
              if (kDebugMode) print('Parsed message: ${message.id} - ${message.content}');
              
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
                    if (kDebugMode) print('✅ WebSocket: Replacing temp message at index $tempIndex with real message ${message.id}');
                    if (kDebugMode) print('   Temp: ${_messages[tempIndex].id}, Real: ${message.id}');
                    
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
                    if (kDebugMode) print('✅ WebSocket: Message updated in UI. Total: ${_messages.length}');
                    
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
                        if (kDebugMode) print('⚠️ WebSocket: Found matching temp message, skipping duplicate add');
                      } else {
                        // ✅ Добавляем сообщение только если нет временного
                        final newMessages = List<Message>.from(_messages);
                        newMessages.insert(0, message); // Добавляем в начало (reverse список)
                        _messages = newMessages;
                        if (kDebugMode) {
                          if (kDebugMode) print('✅ WebSocket: Message added to list. Total: ${_messages.length}');
                        }
                        // Звук/вибрация при новом сообщении от другого пользователя
                        if (message.userId != widget.userId.toString()) {
                          NotificationFeedbackService.onNewMessage();
                        }
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
                        if (kDebugMode) print('✅ WebSocket: Message updated at index $existingIndex. Total: ${_messages.length}');
                      } else {
                        if (kDebugMode) print('⚠️ WebSocket: Message exists check failed, but index not found');
                      }
                    }
                  }
                });
              }
            } catch (parseError) {
              if (kDebugMode) print('Error parsing Message from WebSocket data: $parseError');
              if (kDebugMode) print('Data: $data');
            }
          } else {
            if (kDebugMode) print('Message is for different chat: $chatId (current: $currentChatId)');
          }
        } catch (e) {
          if (kDebugMode) print('Error processing WebSocket message: $e');
          if (kDebugMode) print('Raw event: $event');
        }
      },
      onError: (error) {
        if (kDebugMode) print('WebSocket error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка WebSocket: $error')),
          );
        }
      },
      onDone: () {
        if (kDebugMode) print('WebSocket connection closed');
      },
    );

    // ✅ Подписываемся на realtime события этого чата
    _subscribeToChatRealtime();

    // Добавляем listener для автоматической подгрузки при скролле вверх
    _scrollController.addListener(_onScroll);
  }

  void _sendWsJson(Map<String, dynamic> payload) {
    try {
      if (_channel == null) return;
      _channel!.sink.add(jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) print('Ошибка отправки WS payload: $e');
    }
  }

  void _subscribeToChatRealtime() {
    if (_subscribedToChatRealtime) return;
    if (_channel == null) return;
    _subscribedToChatRealtime = true;
    _sendWsJson({
      'type': 'subscribe',
      'chat_id': widget.chatId,
    });
  }

  void _scheduleTypingCleanup() {
    _typingCleanupTimer?.cancel();
    _typingCleanupTimer = Timer(Duration(seconds: 2), () {
      if (!mounted) return;
      final now = DateTime.now();
      final toRemove = _typingUntilByUserId.entries
          .where((e) => e.value.isBefore(now))
          .map((e) => e.key)
          .toList();
      if (toRemove.isEmpty) return;
      setState(() {
        for (final k in toRemove) {
          _typingUntilByUserId.remove(k);
        }
      });
    });
  }

  void _sendTyping(bool isTyping) {
    _sendWsJson({
      'type': 'typing',
      'chat_id': widget.chatId,
      'is_typing': isTyping,
    });
    _sentTyping = isTyping;
  }

  void _handleComposerChanged(String text) {
    final trimmed = text.trim();
    final shouldType = trimmed.isNotEmpty;

    if (shouldType && !_sentTyping) {
      _sendTyping(true);
    }
    if (!shouldType && _sentTyping) {
      _sendTyping(false);
    }

    _typingStopTimer?.cancel();
    if (shouldType) {
      _typingStopTimer = Timer(Duration(seconds: 2), () {
        if (!mounted) return;
        if (_sentTyping) _sendTyping(false);
      });
    }
  }

  String _buildChatStatusLine() {
    final now = DateTime.now();
    final typingIds = _typingUntilByUserId.entries
        .where((e) => e.value.isAfter(now))
        .map((e) => e.key)
        .where((id) => id != widget.userId.toString())
        .toList();

    if (typingIds.isNotEmpty) {
      final names = typingIds
          .map((id) => _memberEmailById[id] ?? 'Пользователь')
          .toList();
      if (names.length == 1) return '${names.first} печатает…';
      if (names.length == 2) return '${names[0]} и ${names[1]} печатают…';
      return 'Несколько участников печатают…';
    }

    // online count (кроме себя)
    final onlineOthers = _onlineUserIds.where((id) => id != widget.userId.toString()).length;
    if (onlineOthers > 0) return 'Онлайн: $onlineOthers';

    return 'Вы: ${widget.userEmail}';
  }

  Future<void> _initWebSocket() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        return;
      }

      // Подключаемся к WebSocket:
      // - web: через query param (нет возможности поставить Authorization header)
      // - mobile/desktop: через Authorization header (не светим токен в URL)
      if (kIsWeb) {
        _channel = WebSocketChannel.connect(
          Uri.parse('wss://my-server-chat.onrender.com?token=$token'),
        );
      } else {
        _channel = IOWebSocketChannel.connect(
          Uri.parse('wss://my-server-chat.onrender.com'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
      
      // Настраиваем слушатель после подключения
      if (mounted) {
        _setupWebSocketListener();
      }
    } catch (e) {
      // Не логируем чувствительные данные
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
        if (kDebugMode) print('✅ Загружено ${cachedMessages.length} сообщений из кэша');
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ Ошибка загрузки из кэша: $e');
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
      if (kDebugMode) print('Error loading messages: $e');
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
      if (kDebugMode) print('Error loading more messages: $e');
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
        color = Colors.white.withValues(alpha:0.6);
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = Colors.white.withValues(alpha:0.6);
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
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: ['jpg', 'jpeg', 'jpe', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tiff', 'tif', 'avif', 'ico', 'svg'],
      );

      if (result != null && result.files.single.size > 0) {
        final file = result.files.single;
        
        final fileName = file.name.toLowerCase();
        const allowedExtensions = ['.jpg', '.jpeg', '.jpe', '.png', '.gif', '.webp', '.heic', '.heif', '.bmp', '.tiff', '.tif', '.avif', '.ico', '.svg'];
        final hasValidExtension = allowedExtensions.any((ext) => fileName.endsWith(ext));
        
        if (!hasValidExtension) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Неподдерживаемый формат. Используйте: JPEG, PNG, GIF, WEBP, HEIC, BMP, TIFF, AVIF, ICO, SVG'),
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

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: kIsWeb,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      setState(() {
        _selectedFileName = file.name;
        _selectedFileSize = file.size;
        if (kIsWeb) {
          _selectedFileBytes = file.bytes;
          _selectedFilePath = null;
        } else {
          _selectedFilePath = file.path;
          _selectedFileBytes = null;
        }
      });
    } catch (e) {
      if (kDebugMode) print('Ошибка выбора файла: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выбрать файл')),
      );
    }
  }

  /// Обработка перетаскивания файлов (drag-and-drop с рабочего стола)
  Future<void> _handleFilesDropped(DropDoneDetails details) async {
    if (_isRecordingVoice || _isUploadingImage || _isUploadingFile) return;
    final items = details.files;
    if (items.isEmpty) return;

    // Берём первый файл (папки пропускаем)
    final DropItem? fileItem = items.firstWhere(
      (item) => item is! DropItemDirectory,
      orElse: () => items.first,
    );
    if (fileItem is DropItemDirectory) return;

    try {
      final bytes = await fileItem!.readAsBytes();
      final fileName = fileItem.name;
      if (bytes.isEmpty) return;

      final parts = fileName.toLowerCase().split('.');
      final ext = parts.length > 1 ? parts.last : '';
      final imageExtensions = ['jpg', 'jpeg', 'jpe', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tiff', 'tif', 'avif', 'ico', 'svg'];

      if (imageExtensions.contains(ext)) {
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImagePath = null;
          _selectedImageName = fileName;
          _selectedFilePath = null;
          _selectedFileBytes = null;
          _selectedFileName = null;
          _selectedFileSize = null;
        });
      } else {
        setState(() {
          _selectedFileBytes = bytes;
          _selectedFilePath = null;
          _selectedFileName = fileName;
          _selectedFileSize = bytes.length;
          _selectedImagePath = null;
          _selectedImageBytes = null;
          _selectedImageName = null;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл добавлен: $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при добавлении файла: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024.0;
    return '${gb.toStringAsFixed(1)} GB';
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
        if (kDebugMode) print('⚠️  Не удалось декодировать изображение, возвращаем оригинал');
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
          if (kDebugMode) print('📦 Сжатие (качество): ${imageBytes.length} → ${compressedBytes.length} байт (${(savedBytes / imageBytes.length * 100).toStringAsFixed(1)}% меньше)');
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
      if (kDebugMode) print('📦 Сжатие изображения: ${imageBytes.length} → ${compressedBytes.length} байт ($savedPercent% меньше, ${originalImage.width}x${originalImage.height} → ${newWidth}x${newHeight})');
      
      return compressedBytes;
    } catch (e) {
      if (kDebugMode) print('⚠️  Ошибка сжатия изображения: $e, возвращаем оригинал');
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

  bool _looksLikeAudio({String? mime, String? fileName}) {
    final m = (mime ?? '').toLowerCase().trim();
    final n = (fileName ?? '').toLowerCase().trim();
    if (m.startsWith('audio/')) return true;
    return n.endsWith('.m4a') ||
        n.endsWith('.aac') ||
        n.endsWith('.mp3') ||
        n.endsWith('.ogg') ||
        n.endsWith('.opus') ||
        n.endsWith('.wav');
  }

  bool _isVoiceMessage(Message msg) {
    if (msg.messageType == 'voice' || msg.messageType == 'text_voice') return true;
    if (!msg.hasFile) return false;
    return _looksLikeAudio(mime: msg.fileMime, fileName: msg.fileName);
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isUploadingImage || _isUploadingFile) return;
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Голосовые сообщения пока не поддерживаются в веб-версии')),
      );
      return;
    }
    if (_isRecordingVoice) {
      await _stopAndSendVoiceRecording();
    } else {
      await _startVoiceRecording();
    }
  }

  Future<void> _startVoiceRecordingIfNotRecording() async {
    if (_isRecordingVoice) return;
    await _startVoiceRecording();
  }

  Future<void> _stopAndSendVoiceRecordingIfRecording() async {
    if (!_isRecordingVoice) return;
    await _stopAndSendVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    if (!mounted) return;
    // на всякий: не даём начать при выбранных вложениях
    if (_selectedImagePath != null ||
        _selectedImageBytes != null ||
        _selectedFilePath != null ||
        _selectedFileBytes != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сначала отправьте/уберите вложение, затем запишите голосовое')),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    final hasPermission = await _voiceRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Нет доступа к микрофону. Разрешите доступ в настройках.')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _voiceRecordTempPath = path;

    await _voiceRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );

    _voiceRecordTimer?.cancel();
    setState(() {
      _isRecordingVoice = true;
      _voiceRecordDuration = Duration.zero;
    });
    _voiceRecordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _voiceRecordDuration += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _cancelVoiceRecording() async {
    HapticFeedback.lightImpact();
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;

    try {
      await _voiceRecorder.stop();
    } catch (_) {}

    final tmp = _voiceRecordTempPath;
    _voiceRecordTempPath = null;
    if (tmp != null) {
      try {
        final f = File(tmp);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _voiceRecordDuration = Duration.zero;
    });
  }

  Future<void> _stopAndSendVoiceRecording() async {
    HapticFeedback.mediumImpact();
    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;

    String? recordedPath;
    try {
      recordedPath = await _voiceRecorder.stop();
    } catch (_) {}

    final tmp = recordedPath ?? _voiceRecordTempPath;
    _voiceRecordTempPath = null;

    if (tmp == null || tmp.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordDuration = Duration.zero;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить запись')),
      );
      return;
    }

    try {
      final file = File(tmp);
      final bytes = await file.readAsBytes();
      final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // ✅ Убираем режим записи + подставляем файл как вложение и отправляем обычным путём
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordDuration = Duration.zero;

        _selectedFileBytes = bytes;
        _selectedFileName = name;
        _selectedFileSize = bytes.length;
        _selectedFilePath = null;
      });

      // удаляем временный файл — дальше работаем с bytes
      try {
        await file.delete();
      } catch (_) {}

      await _sendMessage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordDuration = Duration.zero;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка записи: $e')),
      );
    }
  }

  Future<void> _toggleVoicePlayback(Message msg) async {
    final url = msg.fileUrl;
    if (url == null || url.isEmpty) return;

    HapticFeedback.lightImpact();

    final same = _voicePlayingMessageId == msg.id;
    try {
      if (same && _voiceIsPlaying) {
        await _voicePlayer.pause();
        return;
      }

      if (!same) {
        setState(() {
          _voicePlayingMessageId = msg.id;
          _voicePosition = Duration.zero;
          _voiceDuration = null;
        });
        await _voicePlayer.setUrl(url);
      }

      await _voicePlayer.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voicePlayingMessageId = null;
        _voicePosition = Duration.zero;
        _voiceDuration = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось воспроизвести аудио: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Widget _buildVoiceBubble(Message msg, {required bool isMine}) {
    final isCurrent = _voicePlayingMessageId == msg.id;
    final dur = isCurrent ? (_voiceDuration ?? Duration.zero) : Duration.zero;
    final pos = isCurrent ? _voicePosition : Duration.zero;

    final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
    final posMs = pos.inMilliseconds.clamp(0, maxMs);

    final isBusy = isCurrent &&
        (_voiceProcessingState == ProcessingState.loading ||
            _voiceProcessingState == ProcessingState.buffering);
    final showPlaying = isCurrent && _voiceIsPlaying;

    final playColor = isMine ? Colors.white : _accent1;
    final trackInactive = isMine ? Colors.white.withValues(alpha:0.35) : Colors.grey.shade300;

    return Container(
      constraints: BoxConstraints(minWidth: 220, maxWidth: 280),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withValues(alpha:0.2) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMine ? Colors.white.withValues(alpha:0.3) : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:isMine ? 0.06 : 0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBusy)
            SizedBox(
              width: 40,
              height: 40,
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(playColor),
                ),
              ),
            )
          else
            Material(
              color: isMine ? Colors.white.withValues(alpha:0.25) : Colors.white,
              shape: CircleBorder(),
              elevation: 0,
              shadowColor: Colors.transparent,
              child: InkWell(
                customBorder: CircleBorder(),
                onTap: () => _toggleVoicePlayback(msg),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: Icon(
                    showPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 24,
                    color: playColor,
                  ),
                ),
              ),
            ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: playColor,
                    inactiveTrackColor: trackInactive,
                    thumbColor: playColor,
                  ),
                  child: Slider(
                    value: posMs.toDouble(),
                    min: 0,
                    max: maxMs.toDouble(),
                    onChanged: isCurrent
                        ? (v) {
                            setState(() {
                              _voicePosition = Duration(milliseconds: v.toInt());
                            });
                          }
                        : null,
                    onChangeEnd: isCurrent
                        ? (v) async {
                            try {
                              await _voicePlayer.seek(Duration(milliseconds: v.toInt()));
                            } catch (_) {}
                          }
                        : null,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _formatDuration(pos),
                      style: TextStyle(
                        fontSize: 12,
                        color: isMine ? Colors.white70 : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Spacer(),
                    Text(
                      dur == Duration.zero ? '—:—' : _formatDuration(dur),
                      style: TextStyle(
                        fontSize: 12,
                        color: isMine ? Colors.white70 : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (kDebugMode) print('🔍 _sendMessage called');
    if (!mounted) {
      if (kDebugMode) print('⚠️ Widget not mounted, returning');
      return;
    }
    
    final text = _controller.text.trim();
    final hasImage = _selectedImagePath != null || _selectedImageBytes != null;
    final hasFile = _selectedFilePath != null || _selectedFileBytes != null;
    
    if (kDebugMode) print('🔍 Text: "$text", hasImage: $hasImage, hasFile: $hasFile');
    
    if (text.isEmpty && !hasImage && !hasFile) {
      if (kDebugMode) print('⚠️ Text is empty and no attachments, returning');
      return;
    }
    
    if (kDebugMode) print('✅ Proceeding with message send');

    // ✅ Останавливаем typing-индикатор перед отправкой
    if (_sentTyping) {
      _typingStopTimer?.cancel();
      _sendTyping(false);
    }

    String? imageUrl;
    String? fileUrl;
    String? fileName;
    int? fileSize;
    String? fileMime;

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

    // Загружаем файл, если выбран
    if (hasFile) {
      // Сервер сейчас не поддерживает "image+file" в одном сообщении
      if (hasImage) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Нельзя отправить изображение и файл в одном сообщении')),
          );
        }
        return;
      }

      setState(() => _isUploadingFile = true);
      try {
        List<int> bytes;
        String name;
        
        // ✅ Поддержка bytes и на мобилках (нужно для voice-recording)
        if (_selectedFileBytes != null) {
          bytes = _selectedFileBytes!;
          name = _selectedFileName ?? 'file';
        } else if (_selectedFilePath != null) {
          final f = File(_selectedFilePath!);
          bytes = await f.readAsBytes();
          name = _selectedFileName ?? _selectedFilePath!.split('/').last;
        } else {
          throw Exception('Файл не выбран');
        }

        final meta = await _messagesService.uploadFile(bytes, name);
        fileUrl = meta['file_url']?.toString();
        fileName = (meta['file_name'] ?? name).toString();
        fileSize = int.tryParse((meta['file_size'] ?? '').toString()) ?? _selectedFileSize ?? bytes.length;
        fileMime = (meta['file_mime'] ?? '').toString();

        if (fileUrl == null || fileUrl.isEmpty) {
          throw Exception('Сервер не вернул file_url');
        }

        if (mounted) {
          setState(() {
            _selectedFilePath = null;
            _selectedFileBytes = null;
            _selectedFileName = null;
            _selectedFileSize = null;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isUploadingFile = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки файла: ${e.toString().replaceFirst('Exception: ', '')}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      setState(() => _isUploadingFile = false);
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
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      fileMime: fileMime,
      messageType: fileUrl != null
          ? (_looksLikeAudio(mime: fileMime, fileName: fileName)
              ? (text.isNotEmpty ? 'text_voice' : 'voice')
              : (text.isNotEmpty ? 'text_file' : 'file'))
          : (imageUrl != null ? (text.isNotEmpty ? 'text_image' : 'image') : 'text'),
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
      if (kDebugMode) print('🔍 Adding temp message to UI: id=$tempMessageId, content=$text');
      if (kDebugMode) print('🔍 Current messages count before: ${_messages.length}');
      if (kDebugMode) print('🔍 Was at bottom before adding: $wasAtBottom');
      if (kDebugMode) print('🔍 Saved scroll position: $savedScrollPosition');
      setState(() {
        // ✅ Создаем новый список для гарантированного обновления UI
        final newMessages = List<Message>.from(_messages);
        newMessages.add(tempMessage); // Добавляем в конец, чтобы новые были снизу
        _messages = newMessages;
        // Очищаем поле ответа
        _replyToMessage = null;
      });
      if (kDebugMode) print('✅ Temp message added to UI. New count: ${_messages.length}');
      if (kDebugMode) print('✅ First message ID: ${_messages.isNotEmpty ? _messages[0].id : "none"}');
      
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
                if (kDebugMode) print('✅ Jumped to bottom (was at bottom, staying there). New maxScroll: $maxScroll');
              } else {
                if (kDebugMode) print('✅ Was not at bottom, keeping current position');
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
      if (kDebugMode) {
        // ignore: avoid_print
        if (kDebugMode) print('sendMessage: chatId=${widget.chatId}, replyTo=$replyToMessageId');
      }
      final sentMessage = await _messagesService.sendMessage(
        widget.chatId, 
        text, 
        imageUrl: imageUrl,
        replyToMessageId: replyToMessageId,
        fileUrl: fileUrl,
        fileName: fileName,
        fileSize: fileSize,
        fileMime: fileMime,
      );
      if (kDebugMode) print('🔍 sendMessage service returned: ${sentMessage != null ? "message with id=${sentMessage.id}" : "null"}');
      
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
        if (_selectedFilePath != null || _selectedFileBytes != null) {
          setState(() {
            _selectedFilePath = null;
            _selectedFileBytes = null;
            _selectedFileName = null;
            _selectedFileSize = null;
          });
        }
        
        // ✅ Если получили сообщение от сервера, обновляем временное сообщение
        if (sentMessage != null) {
          if (kDebugMode) print('✅ Received message from server: id=${sentMessage.id}, content=${sentMessage.content}');
          if (kDebugMode) print('🔍 Looking for temp message with id: $tempMessageId');
          if (kDebugMode) print('🔍 Current messages count: ${_messages.length}');
          if (kDebugMode) print('🔍 Current message IDs: ${_messages.map((m) => m.id).toList()}');
          
          // ✅ Обновляем сразу, без WidgetsBinding, чтобы не потерять сообщение
          final tempIndex = _messages.indexWhere((m) => m.id == tempMessageId);
          if (kDebugMode) print('🔍 Looking for temp message with id: $tempMessageId');
          if (kDebugMode) print('🔍 Current messages count: ${_messages.length}');
          if (kDebugMode) print('🔍 Current message IDs: ${_messages.map((m) => m.id).toList()}');
          if (kDebugMode) print('🔍 Temp message found at index: $tempIndex');
          
          if (tempIndex != -1) {
            if (kDebugMode) print('✅ Replacing temp message at index $tempIndex with real message ${sentMessage.id}');
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
            if (kDebugMode) print('✅ Message updated in UI (new list created). Total messages: ${_messages.length}');
            if (kDebugMode) print('✅ Message IDs after update: ${_messages.map((m) => m.id).toList()}');
          } else {
            // Если временное сообщение не найдено, проверяем, нет ли уже такого сообщения
            final existingIndex = _messages.indexWhere((m) => m.id == sentMessage.id);
            if (existingIndex != -1) {
              if (kDebugMode) print('⚠️ Message already exists at index $existingIndex');
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
              if (kDebugMode) print('✅ Message updated in place at index $existingIndex');
            } else {
              if (kDebugMode) print('⚠️ Temp message not found and message not in list, adding it');
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
              if (kDebugMode) print('✅ Message added to end. Total: ${_messages.length} (new list created)');
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
                    if (kDebugMode) print('✅ Jumped to bottom after message update (was at bottom)');
                  } else {
                    // Если не был внизу - не скроллим, пользователь сам прокрутит
                    if (kDebugMode) print('✅ Was not at bottom, keeping current position');
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
          if (kDebugMode) print('⚠️ No message received from server response');
        }
        
        // ✅ Fallback: Если через 3 секунды временное сообщение все еще есть,
        // значит WebSocket не получил сообщение - оставляем как есть
        // (сообщение уже обновлено из ответа сервера выше)
        Future.delayed(Duration(seconds: 3), () {
          if (mounted && _messages.any((m) => m.id == tempMessageId)) {
            if (kDebugMode) print('⚠️ Temp message still exists after 3s, but should be replaced by WebSocket or server response');
          }
        });
      }
      
      // ✅ Сообщение уже обновлено из ответа сервера
      // Также будет обновлено через WebSocket (если придет) для синхронизации с другими клиентами
      
    } catch (e, stackTrace) {
      if (kDebugMode) print('❌ Error sending message: $e');
      if (kDebugMode) print('❌ Stack trace: $stackTrace');
      
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
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final canEdit = isMine && message.hasText && !message.hasImage && !message.hasFile;

        Widget chip({
          required IconData icon,
          required String label,
          required String value,
        }) {
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context, value),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outline.withValues(alpha:isDark ? 0.18 : 0.12)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: scheme.onSurface.withValues(alpha:0.85)),
                  SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
                  ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            padding: EdgeInsets.fromLTRB(14, 8, 14, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0xFF161A22), Color(0xFF11131A)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF7F8FF)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outline.withValues(alpha:isDark ? 0.18 : 0.10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:isDark ? 0.40 : 0.12),
                  blurRadius: 20,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Действия',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: scheme.onSurface.withValues(alpha:0.65),
                    ),
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    chip(icon: Icons.reply_rounded, label: 'Ответить', value: 'reply'),
                    chip(icon: Icons.forward_rounded, label: 'Переслать', value: 'forward'),
                    chip(icon: Icons.emoji_emotions_rounded, label: 'Реакция', value: 'reaction'),
                    if (canEdit) chip(icon: Icons.edit_rounded, label: 'Редакт.', value: 'edit'),
                  ],
                ),
                SizedBox(height: 12),
                Divider(height: 1, color: scheme.outline.withValues(alpha:isDark ? 0.20 : 0.12)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    message.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    color: scheme.onSurface.withValues(alpha:0.85),
                  ),
                  title: Text(message.isPinned ? 'Открепить' : 'Закрепить'),
                  onTap: () => Navigator.pop(context, message.isPinned ? 'unpin' : 'pin'),
                ),
                if (isMine) ...[
                  Divider(height: 1, color: scheme.outline.withValues(alpha:isDark ? 0.20 : 0.12)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                    title: Text('Удалить', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w700)),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
      if (kDebugMode) print('Ошибка удаления сообщения: $e');
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
      if (kDebugMode) print('Ошибка очистки чата: $e');
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
    _typingStopTimer?.cancel();
    _typingCleanupTimer?.cancel();
    _voiceRecordTimer?.cancel();
    if (_isRecordingVoice) {
      // best-effort: остановим запись
      _voiceRecorder.stop();
    }
    _voicePositionSub?.cancel();
    _voiceDurationSub?.cancel();
    _voicePlayerStateSub?.cancel();
    _voicePlayer.dispose();
    _voiceRecorder.dispose();
    // best-effort: остановим typing и отпишемся
    if (_sentTyping) {
      _sendTyping(false);
    }
    _sendWsJson({'type': 'unsubscribe', 'chat_id': widget.chatId});
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
      if (kDebugMode) print('Ошибка загрузки участников: $e');
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
      if (kDebugMode) print('Ошибка выхода из чата: $e');
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
          if (kDebugMode) print('Ошибка добавления участников: $e');
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
      if (kDebugMode) print('Ошибка загрузки пользователей: $e');
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pinnedHeight = _getPinnedMessagesHeight();
    final scaffoldBg = isDark ? Theme.of(context).scaffoldBackgroundColor : Colors.white;
    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: scaffoldBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _chatTitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              _buildChatStatusLine(),
              style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha:0.65)),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha:0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.search_rounded, color: _accent1),
              onPressed: _openSearch,
              tooltip: 'Поиск по сообщениям',
            ),
          ),
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha:0.10),
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
                  color: _accent1.withValues(alpha:0.25),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: widget.isGroup
                ? IconButton(
                    icon: Icon(Icons.person_add_rounded, color: Colors.white),
                    onPressed: _showAddMembersDialog,
                    tooltip: 'Добавить участников',
                  )
                : SizedBox.shrink(),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: scheme.onSurface.withValues(alpha:0.75)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'clear') _clearChat();
              if (value == 'leave') _leaveChat();
              if (value == 'invite' && widget.isGroup) _showInviteDialog();
              if (value == 'rename' && widget.isGroup) _renameGroupChatDialog();
            },
            itemBuilder: (context) => [
              if (widget.isGroup)
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_rounded, color: Colors.blueGrey.shade700, size: 20),
                      SizedBox(width: 10),
                      Text('Переименовать'),
                    ],
                  ),
                ),
              if (widget.isGroup)
                PopupMenuItem(
                  value: 'invite',
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded, color: Colors.green.shade700, size: 20),
                      SizedBox(width: 10),
                      Text('Пригласить (код)'),
                    ],
                  ),
                ),
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
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingFile = true),
        onDragExited: (_) => setState(() => _isDraggingFile = false),
        onDragDone: _handleFilesDropped,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Container(
                    color: scaffoldBg,
                    child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(_accent1),
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Загрузка сообщений...',
                          style: TextStyle(
                            fontSize: 15,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : _listEntries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 64, color: _accent1.withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text(
                              'Нет сообщений',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Напишите первое сообщение',
                              style: TextStyle(
                                fontSize: 14,
                                color: scheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
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
                          cacheExtent: 800, // Предзагрузка элементов для плавного скролла
                          addAutomaticKeepAlives: false, // Меньше памяти при длинных списках
                          itemCount: _listEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _listEntries[index];
                          if (entry is _LoadMoreEntry) {
                            return Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: OutlinedButton.icon(
                                  onPressed: _loadMoreMessages,
                                  icon: Icon(Icons.arrow_upward, size: 18),
                                  label: Text('Загрузить старые сообщения'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _accent1,
                                    side: BorderSide(color: _accent1.withValues(alpha:0.35), width: 1.5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          if (entry is _LoadingEntry) {
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
                          if (entry is _DateHeaderEntry) {
                            return _buildDateHeader(entry.label);
                          }
                          final msg = _messages[(entry as _MessageEntry).index];
                    final isMine = msg.senderEmail == widget.userEmail;

                final isHighlighted = _highlightMessageId == msg.id;
                return RepaintBoundary(
                  child: AnimatedContainer(
                  key: _keyForMessage(msg.id),
                  duration: Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isHighlighted ? _accent1.withValues(alpha:0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                              color: isMine ? null : Theme.of(context).cardColor,
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
                                      .withValues(alpha:0.2),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                              border: isMine
                                  ? null
                                  : Border.all(
                                      color: scheme.outline.withValues(alpha:isDark ? 0.18 : 0.12),
                                      width: 1.2,
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
                                          ? Colors.white.withValues(alpha:0.2)
                                          : (isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04)),
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
                                                ? Colors.white.withValues(alpha:0.9)
                                                : _accent1,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        if (msg.replyToMessage!.hasFile)
                                          Row(
                                            children: [
                                              Icon(Icons.insert_drive_file_rounded, size: 14, color: isMine ? Colors.white70 : Colors.grey.shade600),
                                              SizedBox(width: 4),
                                              Text(
                                                msg.replyToMessage!.fileName ?? 'Файл',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isMine ? Colors.white70 : Colors.grey.shade600,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          )
                                        else if (msg.replyToMessage!.hasImage)
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
                                // Отображение изображения (открытие в стиле Telegram/WhatsApp)
                                if (msg.hasImage) ...[
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        PageRouteBuilder(
                                          opaque: true,
                                          barrierColor: Colors.black,
                                          pageBuilder: (_, __, ___) => _FullScreenImageViewer(
                                            imageUrl: msg.imageUrl!,
                                            originalImageUrl: msg.originalImageUrl ?? msg.imageUrl,
                                            fileName: msg.imageUrl?.split('/').last ?? 'image.jpg',
                                            onDownload: () => _downloadImage(
                                              msg.originalImageUrl ?? msg.imageUrl!,
                                              msg.imageUrl?.split('/').last ?? 'image.jpg',
                                            ),
                                          ),
                                          transitionsBuilder: (_, animation, __, child) {
                                            return FadeTransition(opacity: animation, child: child);
                                          },
                                          transitionDuration: Duration(milliseconds: 200),
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
                                        child: CachedNetworkImage(
                                          imageUrl: msg.imageUrl!,
                                          fit: BoxFit.contain,
                                          memCacheWidth: 500,
                                          httpHeaders: kIsWeb ? {'Access-Control-Allow-Origin': '*'} : null,
                                          placeholder: (_, __) => Container(
                                            width: 250,
                                            height: 200,
                                            color: Colors.grey.shade200,
                                            child: Center(child: CircularProgressIndicator()),
                                          ),
                                          errorWidget: (context, url, error) {
                                            if (kDebugMode) {
                                              print('Image load error: $error');
                                              print('Image URL: $url');
                                              if (kIsWeb) print('⚠️ ВЕБ: проверьте CORS в Яндекс Облаке');
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
                                                  if (kDebugMode) ...[
                                                    SizedBox(height: 4),
                                                    Text(
                                                      'URL: ${url.length > 50 ? '${url.substring(0, 50)}...' : url}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(fontSize: 10, color: Colors.grey),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  ],
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
                                  if (msg.hasText || msg.hasFile) SizedBox(height: 8),
                                ],
                                // ✅ Отображение файла (attachment)
                                if (msg.hasFile) ...[
                                  if (_isVoiceMessage(msg)) ...[
                                    _buildVoiceBubble(msg, isMine: isMine),
                                  ] else ...[
                                    GestureDetector(
                                      onTap: () async {
                                        final url = Uri.parse(msg.fileUrl!);
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url, mode: LaunchMode.externalApplication);
                                        } else if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Не удалось открыть файл')),
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isMine ? Colors.white.withValues(alpha:0.18) : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isMine ? Colors.white.withValues(alpha:0.25) : Colors.grey.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.insert_drive_file_rounded, size: 18, color: isMine ? Colors.white : _accent2),
                                            SizedBox(width: 8),
                                            Flexible(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    msg.fileName ?? 'Файл',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: isMine ? Colors.white : Colors.grey.shade900,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  if (msg.fileSize != null)
                                                    Text(
                                                      _formatBytes(msg.fileSize!),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: isMine ? Colors.white70 : Colors.grey.shade600,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Icon(Icons.open_in_new_rounded, size: 16, color: isMine ? Colors.white70 : Colors.grey.shade600),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                                // Отображение текста (входящие — светлый текст в тёмной теме для читаемости)
                                if (msg.hasText) ...[
                                  Text(
                                    msg.content,
                                    style: TextStyle(
                                      color: isMine
                                          ? Colors.white
                                          : (isDark ? Colors.white.withValues(alpha:0.95) : Colors.grey.shade900),
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
                                                ? Colors.white.withValues(alpha:0.2)
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
                                            ? Colors.white.withValues(alpha:0.8)
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
                                              ? Colors.white.withValues(alpha:0.6)
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
                ));
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
                              color: Colors.white.withValues(alpha:0.97),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _accent1.withValues(alpha:0.18),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha:0.06),
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
                                        color: _accent1.withValues(alpha:0.8),
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
                                          color: _accent1.withValues(alpha:0.12),
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
                                                color: isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: scheme.outline.withValues(alpha:isDark ? 0.18 : 0.12),
                                                  width: 1.2,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.push_pin,
                                                    size: 12,
                                                    color: _accent1.withValues(alpha:0.6),
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
          ),
          Container(
            decoration: BoxDecoration(
              color: scaffoldBg,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.06),
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
                    // ✅ Индикатор очереди офлайн: сообщения будут отправлены при подключении
                    if (_messages.any((m) => m.id.startsWith('temp_')))
                      Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha:0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withValues(alpha:0.35)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_off_rounded, size: 18, color: Colors.orange.shade700),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'В очереди: ${_messages.where((m) => m.id.startsWith('temp_')).length} сообщ. — отправятся при подключении',
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // ✅ Превью ответа на сообщение
                    if (_replyToMessage != null)
                      Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _accent1.withValues(alpha:0.10),
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
                                  if (_replyToMessage!.hasFile)
                                    Row(
                                      children: [
                                        Icon(Icons.insert_drive_file_rounded, size: 14, color: Colors.grey.shade600),
                                        SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            _replyToMessage!.fileName ?? 'Файл',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                              fontStyle: FontStyle.italic,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    )
                                  else if (_replyToMessage!.hasImage)
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
                    // Превью выбранного файла
                    if (_selectedFilePath != null || _selectedFileBytes != null)
                      Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outline.withValues(alpha:isDark ? 0.18 : 0.12)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.insert_drive_file_rounded, color: _accent2),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedFileName ?? 'Файл',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if (_selectedFileSize != null)
                                    Text(
                                      _formatBytes(_selectedFileSize!),
                                      style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha:0.65)),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close, size: 18),
                              onPressed: () {
                                setState(() {
                                  _selectedFilePath = null;
                                  _selectedFileBytes = null;
                                  _selectedFileName = null;
                                  _selectedFileSize = null;
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    // ✅ Индикатор записи голосового
                    if (_isRecordingVoice)
                      Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.shade50,
                              Colors.red.withValues(alpha:0.06),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.red.withValues(alpha:0.2), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha:0.08),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha:0.5),
                                    blurRadius: 6,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Запись: ${_formatDuration(_voiceRecordDuration)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _cancelVoiceRecording,
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.close_rounded, size: 22, color: Colors.red.shade700),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        // Кнопка выбора файла
                        Container(
                          decoration: BoxDecoration(
                            color: _accent2.withValues(alpha:0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            icon: Icon(Icons.attach_file_rounded, color: _accent2),
                            onPressed: _isRecordingVoice ? null : _pickFile,
                            tooltip: 'Прикрепить файл',
                          ),
                        ),
                        SizedBox(width: 8),
                        // Кнопка выбора изображения
                        Container(
                          decoration: BoxDecoration(
                            color: _accent1.withValues(alpha:0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            icon: Icon(Icons.image_rounded, color: _accent1),
                            onPressed: _isRecordingVoice ? null : _pickImage,
                            tooltip: 'Прикрепить изображение',
                          ),
                        ),
                        SizedBox(width: 8),
                        // ✅ Кнопка микрофона
                        Tooltip(
                          message: 'Удерживайте для записи. Отпустите — отправить. Тап — старт/стоп.',
                          child: GestureDetector(
                            onLongPressStart: (_) {
                              if (_isUploadingImage || _isUploadingFile) return;
                              _startVoiceRecordingIfNotRecording();
                            },
                            onLongPressEnd: (_) {
                              if (_isUploadingImage || _isUploadingFile) return;
                              _stopAndSendVoiceRecordingIfRecording();
                            },
                            child: Material(
                              color: (_isRecordingVoice ? Colors.red : _accent1).withValues(alpha:0.12),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: (_isUploadingImage || _isUploadingFile) ? null : _toggleVoiceRecording,
                                child: Container(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                    _isRecordingVoice ? Icons.stop_rounded : Icons.mic_rounded,
                                    color: _isRecordingVoice ? Colors.red.shade700 : _accent1,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: scheme.outline.withValues(alpha:isDark ? 0.18 : 0.12)),
                            ),
                            child: TextField(
                              controller: _controller,
                              decoration: InputDecoration(
                                hintText: 'Введите сообщение...',
                                hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha:0.55)),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              maxLines: null,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: _handleComposerChanged,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        // Кнопка отправки
                        if (_isUploadingImage || _isUploadingFile)
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
                                  color: _accent1.withValues(alpha:0.3),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(Icons.send, color: Colors.white),
                              onPressed: () {
                                if (_isRecordingVoice) return;
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
            if (_isDraggingFile)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: _accent1.withValues(alpha:0.12),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.file_upload_rounded, size: 56, color: _accent1.withValues(alpha:0.9)),
                          SizedBox(height: 12),
                          Text(
                            'Отпустите файл, чтобы прикрепить',
                            style: TextStyle(
                              fontSize: 16,
                              color: scheme.onSurface.withValues(alpha:0.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Полноэкранный просмотр фото в стиле Telegram/WhatsApp: тёмный фон, зум, тап — закрыть.
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String? originalImageUrl;
  final String fileName;
  final VoidCallback? onDownload;

  const _FullScreenImageViewer({
    required this.imageUrl,
    this.originalImageUrl,
    required this.fileName,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Тап по области закрывает (как в Telegram)
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: 1920,
                  httpHeaders: kIsWeb ? {'Access-Control-Allow-Origin': '*'} : null,
                  placeholder: (_, __) => Center(
                    child: CircularProgressIndicator(
                      color: Colors.white70,
                      strokeWidth: 2,
                    ),
                  ),
                  errorWidget: (context, url, error) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, color: Colors.white54, size: 56),
                        SizedBox(height: 16),
                        Text(
                          'Не удалось загрузить изображение',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Верхняя панель: назад + скачать (полупрозрачная, как в мессенджерах)
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Material(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.close_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  if (onDownload != null)
                    Material(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: onDownload,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.download_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
