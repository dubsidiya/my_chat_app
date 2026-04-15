import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../models/message.dart';
import '../services/messages_service.dart';
import '../services/chats_service.dart';
import '../services/moderation_service.dart';
import '../services/local_messages_service.dart'; // ✅ Импорт сервиса кэширования
import '../services/notification_feedback_service.dart';
import '../services/push_notification_service.dart';
import '../services/websocket_service.dart';
import '../services/e2ee_service.dart';
import '../theme/app_colors.dart';
import '../utils/file_name_display.dart';
import '../utils/network_error_helper.dart';
import '../utils/download_text_file.dart';
import '../widgets/chat_date_header.dart';
import '../widgets/chat_empty_messages.dart';
import '../widgets/e2ee_image.dart';
import '../widgets/chat_load_more_button.dart';
import '../widgets/chat_loading_row.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_message_tile.dart';
import '../widgets/fade_scale_in.dart';
import 'add_members_dialog.dart';
import 'chat_members_dialog.dart';
import 'chat_gallery_screen.dart';
import 'user_profile_screen.dart';

/// Элементы списка сообщений: кнопка «ещё», индикатор загрузки, заголовок даты или сообщение
class _ListEntry {}
class _LoadMoreEntry extends _ListEntry {}
class _LoadingEntry extends _ListEntry {}
class _DateHeaderEntry extends _ListEntry { final String label; _DateHeaderEntry(this.label); }
class _MessageEntry extends _ListEntry { final int index; _MessageEntry(this.index); }
enum _OutgoingUiState { queued, sending, error }
class _PendingUploadDraft {
  final String text;
  final String? replyToMessageId;
  final Message? replyToMessage;
  final Uint8List? imageBytes;
  final String? imagePath;
  final String? imageName;
  final Uint8List? fileBytes;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? fileMime;

  const _PendingUploadDraft({
    required this.text,
    this.replyToMessageId,
    this.replyToMessage,
    this.imageBytes,
    this.imagePath,
    this.imageName,
    this.fileBytes,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.fileMime,
  });

  bool get hasImage => imageBytes != null || (imagePath != null && imagePath!.isNotEmpty);
  bool get hasFile => fileBytes != null || (filePath != null && filePath!.isNotEmpty);
}

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String? displayName;
  final String? myAvatarUrl;
  final String chatId;
  final String chatName;
  final bool isGroup;

  const ChatScreen({super.key, 
    required this.userId,
    required this.userEmail,
    this.displayName,
    this.myAvatarUrl,
    required this.chatId,
    required this.chatName,
    required this.isGroup,
  });

  @override
  // ignore: library_private_types_in_public_api
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const String _e2eeReady = 'ready';
  static const String _e2eeMissing = 'missing';
  static const String _e2eeRequesting = 'requesting';
  static const String _e2eeRetryBackoff = 'retryBackoff';
  static const String _e2eeFailed = 'failed';

  static const Color _accent1 = AppColors.primary;
  static const Color _accent2 = AppColors.primaryGlow;
  static const Color _accent3 = AppColors.accent;

  Widget _myAvatarPlaceholder() {
    final initial = widget.userEmail.isNotEmpty ? widget.userEmail[0].toUpperCase() : '?';
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent1, _accent2],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _otherAvatarPlaceholder(String senderEmail) {
    final initial = senderEmail.trim().isNotEmpty ? senderEmail.trim()[0].toUpperCase() : '?';
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent3, _accent2],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messagesService = MessagesService();
  final _chatsService = ChatsService();
  StreamSubscription? _webSocketSubscription;
  final Map<String, GlobalKey> _messageKeys = {};

  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  String? _oldestMessageId;
  bool _isWaitingForE2eeKey = false;
  String _e2eeKeyState = _e2eeMissing;
  static const int _messagesPerPage = 50;
  String? _selectedImagePath;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _isUploadingImage = false;
  /// Защита от двойного нажатия «Отправить» пока идёт отправка.
  bool _isSendingMessage = false;
  bool _isExportingChat = false;
  bool _isRetryingQueuedMessages = false;
  final Map<String, _OutgoingUiState> _tempMessageStates = {};
  final Map<String, _PendingUploadDraft> _pendingUploadDrafts = {};
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

  // ✅ Realtime presence/typing
  final Map<String, String> _memberEmailById = {};
  List<Map<String, dynamic>> _chatMembers = [];
  final Map<String, Map<String, String>> _memberByHandle = {}; // handle -> {id,email,label}
  final Set<String> _onlineUserIds = <String>{};
  final Map<String, DateTime> _typingUntilByUserId = <String, DateTime>{};
  Timer? _typingStopTimer;
  Timer? _typingCleanupTimer;
  bool _sentTyping = false;
  bool _subscribedToChatRealtime = false;
  Timer? _pollTimer; // резервный опрос новых сообщений при проблемах с WebSocket
  late String _chatTitle;

  // ✅ Mentions (@handle)
  int _mentionStart = -1;
  String _mentionQuery = '';
  List<Map<String, String>> _mentionSuggestions = [];

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
              title: const Text('Пригласить в чат'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (code != null && code.isNotEmpty) ...[
                    const Text('Код:'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            code,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded),
                          tooltip: 'Скопировать',
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(duration: Duration(seconds: 3), content: Text('Код скопирован')),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Передайте этот код человеку — он введёт его в “Вступить по коду”.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ] else ...[
                    Text(
                      'Создайте код приглашения. Его можно ограничить по времени и числу использований.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ttlController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'TTL (минуты)',
                        helperText: 'Напр. 60 = 1 час, 1440 = 1 день',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Макс. использований',
                        helperText: 'Напр. 1 или 10',
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Закрыть'),
                ),
                if (code == null || code.isEmpty)
                  ElevatedButton(
                    onPressed: isLoading ? null : create,
                    child: isLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Создать код'),
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
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(dialogContext);
              setLocal(() {
                isLoading = true;
                error = null;
              });
              try {
                final updated = await _chatsService.renameChat(widget.chatId, name);
                final newName = (updated['name'] ?? name).toString();
                if (!mounted) return;
                setState(() => _chatTitle = newName);
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(duration: Duration(seconds: 3), content: Text('Название обновлено')),
                );
              } catch (e) {
                setLocal(() {
                  isLoading = false;
                  error = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              title: const Text('Переименовать чат'),
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
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : save,
                  child: isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Сохранить'),
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
    PushNotificationService.setCurrentChatId(widget.chatId);
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
    
    // Резервный опрос новых сообщений (если WebSocket не доставил)
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _pollForNewMessages();
    });
    
    // ✅ Отмечаем все сообщения как прочитанные при открытии чата
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markChatAsRead();
    });
  }

  /// Опрос последних сообщений с сервера — подхватывает то, что не пришло по WebSocket.
  Future<void> _pollForNewMessages() async {
    if (!mounted || _isLoading) return;
    unawaited(_retryQueuedMessages());
    try {
      final result = await _messagesService.fetchMessagesPaginated(
        widget.chatId,
        limit: 25,
        offset: 0,
        useCache: false,
      );
      if (!mounted) return;
      final existingIds = _messages.map((m) => m.id).toSet();
      final toAdd = <Message>[];
      for (final msg in result.messages) {
        if (!existingIds.contains(msg.id)) {
          toAdd.add(msg);
          existingIds.add(msg.id);
        }
      }
      if (toAdd.isEmpty) return;
      final fromOthers = toAdd.any((m) => m.userId != widget.userId);
      setState(() {
        _messages = List<Message>.from(_messages)..addAll(toAdd);
      });
      if (fromOthers) NotificationFeedbackService.onNewMessage();
      _scrollToBottom();
    } catch (_) {}
  }

  Future<void> _loadChatMembers() async {
    try {
      final members = await _chatsService.getChatMembers(widget.chatId);
      if (!mounted) return;
      setState(() {
        _chatMembers = members;
        _memberEmailById
          ..clear()
          ..addEntries(members.map((m) {
            final id = (m['id'] ?? '').toString();
            final email = (m['email'] ?? '').toString();
            return MapEntry(id, email);
          }).where((e) => e.key.isNotEmpty));

        _memberByHandle
          ..clear()
          ..addEntries(members.map((m) {
            final id = (m['id'] ?? '').toString();
            final email = (m['email'] ?? '').toString();
            final label = (m['displayName'] ?? m['display_name'] ?? email).toString();
            final handle = _handleFromEmail(email);
            return MapEntry(handle, {'id': id, 'email': email, 'label': label});
          }).where((e) => e.key.isNotEmpty && (e.value['id'] ?? '').isNotEmpty));
      });
    } catch (e) {
      // Не критично — presence/typing просто будет без имён
      if (kDebugMode) print('Ошибка загрузки участников (для presence/typing): $e');
    }
  }

  GlobalKey _keyForMessage(String id) {
    return _messageKeys.putIfAbsent(id, () => GlobalKey());
  }

  /// Сливает пришедшее по WebSocket сообщение с уже имеющимся: не затираем непустой контент пустым
  /// (на части устройств/сетей WS может прийти с пустым content).
  Message _mergeMessageKeepContent(Message existing, Message incoming) {
    if (incoming.content.isNotEmpty || (incoming.imageUrl ?? '').isNotEmpty || (incoming.fileUrl ?? '').isNotEmpty) return incoming;
    return Message(
      id: incoming.id,
      chatId: incoming.chatId,
      userId: incoming.userId,
      content: incoming.content.isNotEmpty ? incoming.content : existing.content,
      imageUrl: (incoming.imageUrl ?? '').isNotEmpty ? incoming.imageUrl : existing.imageUrl,
      originalImageUrl: (incoming.originalImageUrl ?? '').isNotEmpty ? incoming.originalImageUrl : existing.originalImageUrl,
      fileUrl: (incoming.fileUrl ?? '').isNotEmpty ? incoming.fileUrl : existing.fileUrl,
      fileName: incoming.fileName ?? existing.fileName,
      fileSize: incoming.fileSize ?? existing.fileSize,
      fileMime: incoming.fileMime ?? existing.fileMime,
      messageType: incoming.messageType,
      senderEmail: incoming.senderEmail.isNotEmpty ? incoming.senderEmail : existing.senderEmail,
      senderAvatarUrl: (incoming.senderAvatarUrl ?? '').trim().isNotEmpty ? incoming.senderAvatarUrl : existing.senderAvatarUrl,
      createdAt: incoming.createdAt.isNotEmpty ? incoming.createdAt : existing.createdAt,
      deliveredAt: incoming.deliveredAt ?? existing.deliveredAt,
      editedAt: incoming.editedAt ?? existing.editedAt,
      isRead: incoming.isRead,
      readAt: incoming.readAt ?? existing.readAt,
      replyToMessageId: incoming.replyToMessageId ?? existing.replyToMessageId,
      replyToMessage: incoming.replyToMessage ?? existing.replyToMessage,
      isPinned: incoming.isPinned,
      reactions: incoming.reactions ?? existing.reactions,
      isForwarded: incoming.isForwarded,
      originalChatName: incoming.originalChatName ?? existing.originalChatName,
      keyVersion: incoming.keyVersion > 0 ? incoming.keyVersion : existing.keyVersion,
    );
  }

  /// Прокрутить список к самому низу (к новым сообщениям).
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients && _messages.isNotEmpty) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          _scrollController.jumpTo(maxScroll);
        }
      }
    });
  }

  Future<void> _scrollToMessage(String messageId) async {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
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

      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        if (_highlightMessageId == messageId) {
          setState(() => _highlightMessageId = null);
        }
      });
    } catch (e) {
      if (kDebugMode) print('Ошибка перехода к сообщению: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Не удалось перейти к сообщению')),
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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Поиск по сообщениям…',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onChanged: (v) {
                            debounce?.cancel();
                            debounce = Timer(const Duration(milliseconds: 250), () {
                              runSearch(setModalState, v);
                            });
                          },
                        ),
                      ),
                      if (isLoading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(error!, style: const TextStyle(color: Colors.red)),
                        ),
                      Flexible(
                        child: results.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
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
                                separatorBuilder: (_, __) => const Divider(height: 1),
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

  void _openGallery() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatGalleryScreen(
          chatId: widget.chatId,
          chatName: widget.chatName,
        ),
      ),
    );
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
    _webSocketSubscription?.cancel();
    _webSocketSubscription = WebSocketService.instance.stream.listen(
      (event) async {
        if (!mounted) return;
        try {
          final data = event is Map ? event as Map<String, dynamic> : (event is String ? jsonDecode(event) as Map<String, dynamic>? : null);
          if (data == null) return;
          if (kDebugMode) print('WebSocket received: $data');
          
          // Проверяем тип сообщения
          final messageType = data['type'];

          // ✅ Переподключение WebSocket — заново подписываемся на чат
          if (messageType == '_ws_reconnected') {
            if (mounted) {
              _subscribedToChatRealtime = false;
              _subscribeToChatRealtime();
              final currentChatId = widget.chatId.toString();
              // После восстановления сокета подбираем отложенные E2EE-запросы.
              unawaited(E2eeService.processPendingKeyRequests(currentChatId));
              // Если ключ недоступен/в бэкоффе — мягко перезапускаем цикл запроса.
              if (_e2eeKeyState != _e2eeReady) {
                unawaited(_ensureE2eeKeyAndReloadIfMissing(currentChatId));
              }
              // Единая точка ретрая очереди исходящих temp-сообщений.
              unawaited(_retryQueuedMessages());
            }
            return;
          }

          // ✅ E2EE: другой участник запросил ключ чата — отдаём ему ключ, если он у нас есть
          if (messageType == 'e2ee_request_key') {
            final chatId = data['chatId']?.toString();
            final requesterUserId = data['userId']?.toString();
            final keyVersion = data['keyVersion'] is int
                ? data['keyVersion'] as int
                : int.tryParse((data['keyVersion'] ?? '').toString());
            if (chatId != null) {
              if (requesterUserId != null && requesterUserId.isNotEmpty) {
                unawaited(E2eeService.shareChatKeyWithUsers(chatId, [requesterUserId], keyVersion: keyVersion));
              } else {
                unawaited(E2eeService.shareChatKeyWithNewMembers(chatId));
              }
            }
            return;
          }

          // ✅ E2EE rotation after member leave/remove: leader bootstraps a fresh key for new version.
          if (messageType == 'e2ee_key_rotated') {
            final chatId = data['chatId']?.toString();
            final keyVersion = data['keyVersion'] is int
                ? data['keyVersion'] as int
                : int.tryParse((data['keyVersion'] ?? '').toString());
            final leaderUserId = data['leaderUserId']?.toString();
            if (chatId == widget.chatId.toString() && keyVersion != null && keyVersion > 0) {
              unawaited(_handleE2eeKeyRotation(chatId!, keyVersion, leaderUserId));
            }
            return;
          }

          // ✅ Новое сообщение (realtime) — type == 'message' просто не возвращаемся, идём к обработке chat_id ниже

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
                  _typingUntilByUserId[uid] = DateTime.now().add(const Duration(seconds: 5));
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
                  _pinnedMessages.removeWhere((m) => m.id.toString() == deletedMessageId);
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
                    senderAvatarUrl: msg.senderAvatarUrl,
                    createdAt: msg.createdAt,
                    deliveredAt: msg.deliveredAt,
                    editedAt: msg.editedAt,
                    isRead: true,
                    readAt: data['read_at']?.toString() ?? DateTime.now().toIso8601String(),
                    keyVersion: msg.keyVersion,
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
                      senderAvatarUrl: msg.senderAvatarUrl,
                      createdAt: msg.createdAt,
                      deliveredAt: msg.deliveredAt,
                      editedAt: msg.editedAt,
                      isRead: true,
                      readAt: data['read_at']?.toString() ?? DateTime.now().toIso8601String(),
                      keyVersion: msg.keyVersion,
                    );
                  }
                }
              });
            }
            return;
          }
          
          // ✅ Обработка события редактирования сообщения (E2EE: контент с сервера может быть зашифрован)
          if (messageType == 'message_edited') {
            final messageId = data['id']?.toString();
            final chatIdWs = data['chat_id']?.toString();
            final currentChatId = widget.chatId.toString();
            if (chatIdWs == currentChatId && messageId != null && mounted) {
              final index = _messages.indexWhere((m) => m.id.toString() == messageId);
              if (index != -1) {
                final msg = _messages[index];
                final rawContent = (data['content'] ?? msg.content).toString();
                final updatedRaw = Message(
                  id: msg.id,
                  chatId: msg.chatId,
                  userId: msg.userId,
                  content: rawContent,
                  imageUrl: data['image_url'] ?? msg.imageUrl,
                  originalImageUrl: msg.originalImageUrl,
                  fileUrl: data['file_url'] ?? msg.fileUrl,
                  fileName: data['file_name'] ?? msg.fileName,
                  fileSize: data['file_size'] ?? msg.fileSize,
                  fileMime: data['file_mime'] as String? ?? msg.fileMime,
                  messageType: data['message_type'] ?? msg.messageType,
                  senderAvatarUrl: data['sender_avatar_url'] ?? msg.senderAvatarUrl,
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
                  keyVersion: msg.keyVersion,
                );
                LocalMessagesService.updateMessage(widget.chatId, updatedRaw);
                final displayMessage = await MessagesService.decryptMessageForChat(currentChatId, updatedRaw);
                if (E2eeService.isEncrypted(updatedRaw.content) && displayMessage.content == '[зашифровано]') {
                  unawaited(_ensureE2eeKeyAndReloadIfMissing(currentChatId, keyVersion: updatedRaw.keyVersion));
                }
                if (mounted) {
                  setState(() {
                    _messages[index] = displayMessage;
                  });
                }
              }
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
                    senderAvatarUrl: msg.senderAvatarUrl,
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
                    keyVersion: msg.keyVersion,
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
              final rawMessage = Message.fromJson(data);
              LocalMessagesService.updateMessage(widget.chatId, rawMessage);
              final message = await MessagesService.decryptMessageForChat(widget.chatId.toString(), rawMessage);
              if (E2eeService.isEncrypted(rawMessage.content) && message.content == '[зашифровано]') {
                unawaited(_ensureE2eeKeyAndReloadIfMissing(currentChatId, keyVersion: rawMessage.keyVersion));
              }
              if (kDebugMode) print('Parsed message: ${message.id} - ${message.content}');
              if (mounted) {
                setState(() {
                  // ✅ Проверяем, есть ли временное сообщение от текущего пользователя
                  // (чтобы заменить его на реальное сообщение от сервера)
                  final tempIndex = _messages.indexWhere((m) => 
                    m.id.startsWith('temp_') && 
                    m.userId == widget.userId.toString() &&
                    // Проверяем содержимое (текст или изображение)
                    ((m.content == message.content && m.content.isNotEmpty) ||
                     (m.imageUrl == message.imageUrl && m.imageUrl != null) ||
                     (m.content.isEmpty && m.imageUrl == null && message.content.isEmpty && message.imageUrl == null))
                  );
                  
                  if (tempIndex != -1) {
                    // ✅ Заменяем временное сообщение на реальное (но не перезаписываем контент пустым — на части устройств WS приходит с пустым content)
                    if (kDebugMode) print('✅ WebSocket: Replacing temp message at index $tempIndex with real message ${message.id}');
                    if (kDebugMode) print('   Temp: ${_messages[tempIndex].id}, Real: ${message.id}');
                    final existing = _messages[tempIndex];
                    final merged = _mergeMessageKeepContent(existing, message);
                    
                    // ✅ Создаем новый список для принудительного обновления UI
                    final newMessages = List<Message>.from(_messages);
                    final tempId = newMessages[tempIndex].id; // Сохраняем ID временного сообщения
                    newMessages[tempIndex] = merged;
                    _messages = newMessages;
                    _tempMessageStates.remove(tempId);
                    _pendingUploadDrafts.remove(tempId);
                    unawaited(LocalMessagesService.removePendingUploadDraft(widget.chatId, tempId));
                    if (kDebugMode) print('✅ WebSocket: Message updated in UI. Total: ${_messages.length}');
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
                        // ⚠️ Защита: на части устройств/сетей может прийти WS-эвент с пустым content для СВОЕГО сообщения.
                        // В этом случае не добавляем "пустышку" — своё сообщение корректно придёт из HTTP-ответа и/или будет заменено.
                        final isSelf = message.userId == widget.userId.toString();
                        final isEmptyTextOnly = message.content.trim().isEmpty &&
                            (message.imageUrl == null || message.imageUrl!.isEmpty) &&
                            (message.fileUrl == null || message.fileUrl!.isEmpty);
                        if (isSelf && isEmptyTextOnly) {
                          if (kDebugMode) print('⚠️ WebSocket: Skip empty self message (id=${message.id})');
                          return;
                        }

                        // ✅ Добавляем сообщение только если нет временного
                        final newMessages = List<Message>.from(_messages);
                        newMessages.add(message); // В конец: список "старые сверху, новые снизу"
                        _messages = newMessages;
                        if (kDebugMode) {
                          if (kDebugMode) print('✅ WebSocket: Message added to list. Total: ${_messages.length}');
                        }
                        // Звук/вибрация при новом сообщении от другого пользователя
                        if (message.userId != widget.userId.toString()) {
                          NotificationFeedbackService.onNewMessage();
                        }
                        _scrollToBottom();
                      }
                    } else {
                      // ✅ Если сообщение уже есть, обновляем (не затираем непустой контент пустым из WS)
                      final existingIndex = _messages.indexWhere((m) => m.id == message.id);
                      if (existingIndex != -1) {
                        final existing = _messages[existingIndex];
                        final merged = _mergeMessageKeepContent(existing, message);
                        final newMessages = List<Message>.from(_messages);
                        newMessages[existingIndex] = merged;
                        
                        if (existingIndex != 0) {
                          newMessages.removeAt(existingIndex);
                          newMessages.insert(0, merged);
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
            SnackBar(duration: const Duration(seconds: 3), content: Text('Ошибка WebSocket: $error')),
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

  bool _sendWsJson(Map<String, dynamic> payload) {
    try {
      return WebSocketService.instance.send(payload);
    } catch (e) {
      if (kDebugMode) print('Ошибка отправки WS payload: $e');
      return false;
    }
  }

  void _subscribeToChatRealtime() {
    if (_subscribedToChatRealtime) return;
    final sent = _sendWsJson({
      'type': 'subscribe',
      'chat_id': widget.chatId,
    });
    if (sent) {
      _subscribedToChatRealtime = true;
    }
  }

  void _scheduleTypingCleanup() {
    _typingCleanupTimer?.cancel();
    _typingCleanupTimer = Timer(const Duration(seconds: 2), () {
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
      _typingStopTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        if (_sentTyping) _sendTyping(false);
      });
    }

    _updateMentionSuggestions(text);
  }

  String _handleFromEmail(String email) {
    final e = email.trim();
    final at = e.indexOf('@');
    final local = (at >= 1 ? e.substring(0, at) : e).trim().toLowerCase();
    if (local.isEmpty) return '';
    // ограничим безопасным набором, чтобы handle был стабильным
    final cleaned = local.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    return cleaned;
  }

  void _updateMentionSuggestions(String text) {
    final sel = _controller.selection;
    int cursor = sel.baseOffset;
    if (cursor < 0 || cursor > text.length) cursor = text.length;

    final prefix = text.substring(0, cursor);
    final at = prefix.lastIndexOf('@');
    if (at == -1) {
      if (_mentionSuggestions.isNotEmpty || _mentionStart != -1) {
        setState(() {
          _mentionStart = -1;
          _mentionQuery = '';
          _mentionSuggestions = [];
        });
      }
      return;
    }

    // '@' должно начинать токен (после пробела/переноса/начала)
    if (at > 0) {
      final prev = prefix[at - 1];
      if (!RegExp(r'\s').hasMatch(prev)) {
        return;
      }
    }

    final q = prefix.substring(at + 1);
    if (q.contains(RegExp(r'\s')) || q.contains('/')) {
      // закрываем overlay, если завершили токен
      if (_mentionSuggestions.isNotEmpty || _mentionStart != -1) {
        setState(() {
          _mentionStart = -1;
          _mentionQuery = '';
          _mentionSuggestions = [];
        });
      }
      return;
    }

    final query = q.toLowerCase();
    final suggestions = <Map<String, String>>[];
    final seen = <String>{};
    for (final m in _chatMembers) {
      final id = (m['id'] ?? '').toString();
      final email = (m['email'] ?? '').toString();
      if (id.isEmpty || email.isEmpty) continue;
      final handle = _handleFromEmail(email);
      if (handle.isEmpty) continue;
      if (seen.contains(handle)) continue;
      final label = (m['displayName'] ?? m['display_name'] ?? email).toString();

      if (query.isNotEmpty) {
        if (!handle.contains(query) && !label.toLowerCase().contains(query) && !email.toLowerCase().contains(query)) {
          continue;
        }
      }

      suggestions.add({'id': id, 'email': email, 'label': label, 'handle': handle});
      seen.add(handle);
      if (suggestions.length >= 8) break;
    }

    final changed = _mentionStart != at || _mentionQuery != query || suggestions.length != _mentionSuggestions.length;
    if (!changed) return;
    setState(() {
      _mentionStart = at;
      _mentionQuery = query;
      _mentionSuggestions = suggestions;
    });
  }

  void _insertMention(String handle) {
    final text = _controller.text;
    final sel = _controller.selection;
    int cursor = sel.baseOffset;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    if (_mentionStart < 0 || _mentionStart >= text.length || _mentionStart > cursor) return;
    final before = text.substring(0, _mentionStart);
    final after = text.substring(cursor);
    final insert = '@$handle ';
    final next = '$before$insert$after';
    final nextCursor = (before.length + insert.length);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
    setState(() {
      _mentionStart = -1;
      _mentionQuery = '';
      _mentionSuggestions = [];
    });
  }

  void _openUserProfileById(String userId, {String? fallbackLabel}) {
    final otherId = userId.toString().trim();
    if (otherId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: otherId,
          fallbackLabel: fallbackLabel,
        ),
      ),
    );
  }

  Future<void> _openMentions() async {
    final myHandle = _handleFromEmail(widget.userEmail);
    if (myHandle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 3), content: Text('Не удалось определить ваш handle')));
      return;
    }
    final query = '@$myHandle';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        List<Map<String, dynamic>> results = [];
        bool isLoading = true;
        String? error;
        bool started = false;

        Future<void> load(StateSetter setModalState) async {
          setModalState(() {
            isLoading = true;
            error = null;
          });
          try {
            final found = await _messagesService.searchMessages(widget.chatId, query, limit: 50);
            setModalState(() {
              results = found;
              isLoading = false;
            });
          } catch (e) {
            // fallback: локальный поиск в уже загруженных сообщениях
            final local = _messages.where((m) => m.content.toLowerCase().contains(query.toLowerCase())).take(50).map((m) => {
              'message_id': m.id,
              'sender_email': m.senderEmail,
              'content_snippet': m.content.length > 80 ? '${m.content.substring(0, 80)}…' : m.content,
              'created_at': m.createdAt,
            }).toList();
            setModalState(() {
              results = local;
              error = e.toString().replaceFirst('Exception: ', '');
              isLoading = false;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!started) {
              started = true;
              scheduleMicrotask(() => load(setModalState));
            }
            final scheme = Theme.of(context).colorScheme;
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outline.withValues(alpha: 0.25)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.alternate_email_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Упоминания $query',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: isLoading ? null : () => load(setModalState),
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'Обновить',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGlow)),
                      )
                    else if (results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Упоминаний пока нет',
                          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outline.withValues(alpha: 0.18)),
                          itemBuilder: (context, index) {
                            final r = results[index];
                            final mid = (r['message_id'] ?? r['id'] ?? '').toString();
                            final sender = (r['sender_email'] ?? '').toString();
                            final snippet = (r['content_snippet'] ?? r['content'] ?? '').toString();
                            return ListTile(
                              title: Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: sender.isEmpty ? null : Text(sender, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: mid.isEmpty
                                  ? null
                                  : () async {
                                      Navigator.pop(sheetContext);
                                      await _jumpToMessage(mid);
                                    },
                            );
                          },
                        ),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          error!,
                          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.55), fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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

    return 'Вы: ${widget.displayName ?? widget.userEmail}';
  }

  Future<void> _initWebSocket() async {
    try {
      await WebSocketService.instance.connectIfNeeded();
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

  /// E2EE: после requestChatKey ждём появления ключа на сервере и перерисовываем сообщения (расшифровка чужих).
  Future<void> _retryChatKeyThenReloadMessages(String chatIdStr, {int? keyVersion}) async {
    if (_isWaitingForE2eeKey) return;
    _isWaitingForE2eeKey = true;
    if (mounted) setState(() => _e2eeKeyState = _e2eeRequesting);
    _showE2eeWaitingSnack();
    final obtained = await E2eeService.waitForChatKeyFromServer(chatIdStr, keyVersion: keyVersion);
    _isWaitingForE2eeKey = false;
    if (obtained && mounted) {
      setState(() => _e2eeKeyState = _e2eeReady);
      _hideE2eeWaitingSnack();
      _showE2eeReadySnack();
      await _loadMessages();
    } else if (mounted) {
      setState(() => _e2eeKeyState = _e2eeRetryBackoff);
      _hideE2eeWaitingSnack();
    }
  }

  Future<void> _ensureE2eeKeyAndReloadIfMissing(String chatIdStr, {int? keyVersion}) async {
    if (_isWaitingForE2eeKey) return;
    if (mounted) setState(() => _e2eeKeyState = _e2eeRequesting);
    await E2eeService.requestChatKey(chatIdStr, keyVersion: keyVersion);
    unawaited(_retryChatKeyThenReloadMessages(chatIdStr, keyVersion: keyVersion));
  }

  Future<void> _handleE2eeKeyRotation(String chatIdStr, int keyVersion, String? leaderUserId) async {
    if (!mounted) return;
    setState(() => _e2eeKeyState = _e2eeMissing);

    final myId = widget.userId.toString();
    final isLeader = leaderUserId != null && leaderUserId == myId;
    if (isLeader) {
      try {
        await E2eeService.ensureKeyPair();
        final members = await _chatsService.getChatMembers(chatIdStr);
        final memberIds = members.map((m) => m['id']?.toString() ?? '').where((x) => x.isNotEmpty).toList();
        final pubKeys = await E2eeService.fetchPublicKeys(memberIds);
        final keysMembers = memberIds
            .map((id) => <String, dynamic>{'id': id, 'publicKey': pubKeys[id] ?? ''})
            .toList();
        await E2eeService.createChatKey(chatIdStr, keysMembers, keyVersion: keyVersion);
        if (mounted) {
          setState(() => _e2eeKeyState = _e2eeReady);
          _showE2eeReadySnack();
        }
        await _loadMessages();
        return;
      } catch (_) {
        // Fall through to request/retry path.
      }
    }

    await _ensureE2eeKeyAndReloadIfMissing(chatIdStr, keyVersion: keyVersion);
  }

  String? _e2eeStatusText() {
    switch (_e2eeKeyState) {
      case _e2eeReady:
        return null;
      case _e2eeMissing:
        return 'Ключ шифрования отсутствует. Запрашиваем...';
      case _e2eeRequesting:
        return 'Ожидаем ключ шифрования от собеседника...';
      case _e2eeRetryBackoff:
        return 'Ключ не получен, повторим запрос автоматически.';
      case _e2eeFailed:
        return 'Не удалось получить ключ шифрования.';
      default:
        return 'Ключ шифрования отсутствует. Запрашиваем...';
    }
  }

  void _showE2eeWaitingSnack() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 20),
        content: Text('Ожидаем ключ шифрования от собеседника...'),
      ),
    );
  }

  void _hideE2eeWaitingSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _showE2eeReadySnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Ключ шифрования получен. Сообщения обновлены.'),
      ),
    );
  }

  Future<void> _loadMessages() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasMoreMessages = true;
      _oldestMessageId = null;
    });

    // Для аккаунтов, которые вошли по сохранённому токену (без ввода пароля),
    // гарантируем локальную E2EE-пару и публикацию public key перед обменом ключами чата.
    try {
      await E2eeService.ensureKeyPair();
    } catch (_) {}

    // Восстанавливаем отложенные вложения/голосовые, пережившие перезапуск приложения.
    await _restorePendingUploadDrafts();
    
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
        // E2EE: считаем требуемую (самую новую в истории) версию ключа.
        final newestMessageKeyVersion = result.messages.fold<int>(
          1,
          (best, m) => m.keyVersion > best ? m.keyVersion : best,
        );
        final knownCurrentVersion = await E2eeService.getCurrentKeyVersion(widget.chatId.toString());
        final requiredKeyVersion = knownCurrentVersion != null && knownCurrentVersion > newestMessageKeyVersion
            ? knownCurrentVersion
            : newestMessageKeyVersion;
        await E2eeService.markCurrentKeyVersion(widget.chatId.toString(), requiredKeyVersion);

        // E2EE: если у нас есть ключ требуемой версии — отдать участникам без ключа; иначе запросить именно эту версию.
        final chatIdStr = widget.chatId.toString();
        final hasKey = await E2eeService.getChatKey(chatIdStr, keyVersion: requiredKeyVersion) != null;
        if (hasKey) {
          if (mounted) setState(() => _e2eeKeyState = _e2eeReady);
          await E2eeService.shareChatKeyWithNewMembers(chatIdStr);
          await E2eeService.processPendingKeyRequests(chatIdStr);
        } else {
          if (mounted) setState(() => _e2eeKeyState = _e2eeMissing);
          await E2eeService.requestChatKey(chatIdStr, keyVersion: requiredKeyVersion);
          unawaited(_retryChatKeyThenReloadMessages(chatIdStr, keyVersion: requiredKeyVersion));
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error loading messages: $e');
      if (mounted) setState(() => _e2eeKeyState = _e2eeFailed);
      // ✅ Если ошибка, но есть кэш - не показываем ошибку
      if (_messages.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки сообщений: ${networkErrorMessage(e)}'),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () => _loadMessages(),
            ),
          ),
        );
      } else if (mounted) {
        // Показываем уведомление об офлайн режиме
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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
        useCache: false,
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
            content: Text('Ошибка загрузки сообщений: ${networkErrorMessage(e)}'),
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
    if (msg.id.startsWith('temp_')) {
      final state = _tempMessageStates[msg.id] ?? _OutgoingUiState.sending;
      switch (state) {
        case _OutgoingUiState.queued:
          return Icon(
            Icons.schedule_rounded,
            size: 14,
            color: Colors.orange.shade300,
          );
        case _OutgoingUiState.sending:
          return Icon(
            Icons.schedule_send_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.7),
          );
        case _OutgoingUiState.error:
          return Icon(
            Icons.error_outline_rounded,
            size: 14,
            color: Colors.red.shade300,
          );
      }
    }

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
        color = AppColors.accent; // прочитано — в стиле темы
        break;
    }
    
    return Icon(
      icon,
      size: 14,
      color: color,
    );
  }

  bool _isQueueableSendError(Object e) {
    final text = e.toString().toLowerCase();
    return text.contains('нет подключения к интернету') ||
        text.contains('socketexception') ||
        text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection reset');
  }

  void _cleanupTempStateCache() {
    final liveTempIds = _messages.where((m) => m.id.startsWith('temp_')).map((m) => m.id).toSet();
    for (final id in liveTempIds) {
      _tempMessageStates.putIfAbsent(id, () => _OutgoingUiState.queued);
    }
    _tempMessageStates.removeWhere((id, _) => !liveTempIds.contains(id));
    final toRemove = _pendingUploadDrafts.keys.where((id) => !liveTempIds.contains(id)).toList();
    for (final id in toRemove) {
      _pendingUploadDrafts.remove(id);
      unawaited(LocalMessagesService.removePendingUploadDraft(widget.chatId, id));
    }
  }

  String _pendingPlaceholderText(_PendingUploadDraft draft) {
    if (draft.text.trim().isNotEmpty) return draft.text.trim();
    if (draft.hasImage) return '🖼️ Изображение (в очереди)';
    if (_looksLikeAudio(mime: draft.fileMime, fileName: draft.fileName)) {
      return '🎤 Голосовое сообщение (в очереди)';
    }
    if (draft.hasFile) return '📎 Файл (в очереди)';
    return 'Сообщение в очереди';
  }

  Map<String, dynamic> _pendingDraftToJson(_PendingUploadDraft draft) {
    return {
      'text': draft.text,
      'replyToMessageId': draft.replyToMessageId,
      'replyToMessage': draft.replyToMessage?.toJson(),
      'imageBytesB64': draft.imageBytes != null ? base64Encode(draft.imageBytes!) : null,
      'imagePath': draft.imagePath,
      'imageName': draft.imageName,
      'fileBytesB64': draft.fileBytes != null ? base64Encode(draft.fileBytes!) : null,
      'filePath': draft.filePath,
      'fileName': draft.fileName,
      'fileSize': draft.fileSize,
      'fileMime': draft.fileMime,
    };
  }

  _PendingUploadDraft? _pendingDraftFromJson(Map<String, dynamic> json) {
    try {
      final replyRaw = json['replyToMessage'];
      Message? reply;
      if (replyRaw is Map) {
        final data = <String, dynamic>{};
        replyRaw.forEach((k, v) => data[k.toString()] = v);
        reply = Message.fromJson(data);
      }
      final imageB64 = json['imageBytesB64']?.toString();
      final fileB64 = json['fileBytesB64']?.toString();
      return _PendingUploadDraft(
        text: (json['text'] ?? '').toString(),
        replyToMessageId: json['replyToMessageId']?.toString(),
        replyToMessage: reply,
        imageBytes: (imageB64 != null && imageB64.isNotEmpty) ? base64Decode(imageB64) : null,
        imagePath: json['imagePath']?.toString(),
        imageName: json['imageName']?.toString(),
        fileBytes: (fileB64 != null && fileB64.isNotEmpty) ? base64Decode(fileB64) : null,
        filePath: json['filePath']?.toString(),
        fileName: json['fileName']?.toString(),
        fileSize: json['fileSize'] is int
            ? json['fileSize'] as int
            : int.tryParse((json['fileSize'] ?? '').toString()),
        fileMime: json['fileMime']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _restorePendingUploadDrafts() async {
    final raw = await LocalMessagesService.getPendingUploadDrafts(widget.chatId);
    if (raw.isEmpty || !mounted) return;

    final existingIds = _messages.map((m) => m.id).toSet();
    final restored = <Message>[];
    raw.forEach((tempId, draftJson) {
      final draft = _pendingDraftFromJson(draftJson);
      if (draft == null) return;
      _pendingUploadDrafts[tempId] = draft;
      _tempMessageStates.putIfAbsent(tempId, () => _OutgoingUiState.queued);
      if (!existingIds.contains(tempId)) {
        restored.add(
          Message(
            id: tempId,
            chatId: widget.chatId,
            userId: widget.userId,
            content: _pendingPlaceholderText(draft),
            fileName: draft.fileName,
            fileSize: draft.fileSize,
            fileMime: draft.fileMime,
            messageType: draft.hasImage
                ? (draft.text.trim().isNotEmpty ? 'text_image' : 'image')
                : (draft.hasFile
                    ? (_looksLikeAudio(mime: draft.fileMime, fileName: draft.fileName)
                        ? (draft.text.trim().isNotEmpty ? 'text_voice' : 'voice')
                        : (draft.text.trim().isNotEmpty ? 'text_file' : 'file'))
                    : 'text'),
            senderEmail: widget.userEmail,
            senderAvatarUrl: widget.myAvatarUrl,
            createdAt: DateTime.now().toIso8601String(),
            replyToMessageId: draft.replyToMessageId,
            replyToMessage: draft.replyToMessage,
            keyVersion: 1,
          ),
        );
      }
    });

    if (restored.isNotEmpty && mounted) {
      setState(() {
        _messages = List<Message>.from(_messages)..addAll(restored);
      });
    }
  }

  void _enqueuePendingUploadDraft(_PendingUploadDraft draft) {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final placeholder = _pendingPlaceholderText(draft);
    final tempMessage = Message(
      id: tempId,
      chatId: widget.chatId,
      userId: widget.userId,
      content: placeholder,
      fileName: draft.fileName,
      fileSize: draft.fileSize,
      fileMime: draft.fileMime,
      messageType: draft.hasImage
          ? (draft.text.trim().isNotEmpty ? 'text_image' : 'image')
          : (draft.hasFile
              ? (_looksLikeAudio(mime: draft.fileMime, fileName: draft.fileName)
                  ? (draft.text.trim().isNotEmpty ? 'text_voice' : 'voice')
                  : (draft.text.trim().isNotEmpty ? 'text_file' : 'file'))
              : 'text'),
      senderEmail: widget.userEmail,
      senderAvatarUrl: widget.myAvatarUrl,
      createdAt: DateTime.now().toIso8601String(),
      replyToMessageId: draft.replyToMessageId,
      replyToMessage: draft.replyToMessage,
      keyVersion: 1,
    );

    setState(() {
      _messages = List<Message>.from(_messages)..add(tempMessage);
      _tempMessageStates[tempId] = _OutgoingUiState.queued;
      _pendingUploadDrafts[tempId] = draft;
      _isUploadingImage = false;
      _isUploadingFile = false;
      _selectedImagePath = null;
      _selectedImageBytes = null;
      _selectedImageName = null;
      _selectedFilePath = null;
      _selectedFileBytes = null;
      _selectedFileName = null;
      _selectedFileSize = null;
      _replyToMessage = null;
    });
    unawaited(LocalMessagesService.savePendingUploadDraft(widget.chatId, tempId, _pendingDraftToJson(draft)));
    _controller.clear();
    _scrollToBottom();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 3),
        content: Text('Нет сети: вложение добавлено в очередь отправки'),
      ),
    );
  }

  Future<Message?> _sendPendingUploadDraft(_PendingUploadDraft draft) async {
    String? imageUrl;
    String? fileUrl;
    String? fileName;
    int? fileSize;
    String? fileMime;

    if (draft.hasImage) {
      Uint8List originalBytes;
      if (draft.imageBytes != null) {
        originalBytes = draft.imageBytes!;
      } else if (draft.imagePath != null && draft.imagePath!.isNotEmpty) {
        originalBytes = await File(draft.imagePath!).readAsBytes();
      } else {
        throw Exception('Изображение для очереди не найдено');
      }
      final compressed = await _compressImage(originalBytes);
      final imgName = draft.imageName ??
          (draft.imagePath != null && draft.imagePath!.isNotEmpty ? draft.imagePath!.split('/').last : 'image.jpg');
      imageUrl = await _messagesService.uploadImage(
        compressed,
        imgName,
        originalBytes: originalBytes,
        chatId: widget.chatId.toString(),
      );
    }

    if (draft.hasFile) {
      List<int> bytes;
      if (draft.fileBytes != null) {
        bytes = draft.fileBytes!;
      } else if (draft.filePath != null && draft.filePath!.isNotEmpty) {
        bytes = await File(draft.filePath!).readAsBytes();
      } else {
        throw Exception('Файл для очереди не найден');
      }
      final name = draft.fileName ??
          (draft.filePath != null && draft.filePath!.isNotEmpty ? draft.filePath!.split('/').last : 'file');
      final meta = await _messagesService.uploadFile(bytes, name);
      fileUrl = meta['file_url']?.toString();
      fileName = (meta['file_name'] ?? name).toString();
      fileSize = int.tryParse((meta['file_size'] ?? '').toString()) ?? draft.fileSize ?? bytes.length;
      fileMime = (meta['file_mime'] ?? draft.fileMime ?? '').toString();
    }

    return _messagesService.sendMessage(
      widget.chatId,
      draft.text,
      imageUrl: imageUrl,
      fileUrl: fileUrl,
      fileName: fileName,
      fileSize: fileSize,
      fileMime: fileMime,
      replyToMessageId: draft.replyToMessageId,
    );
  }

  Future<void> _retryQueuedMessages() async {
    if (!mounted || _isRetryingQueuedMessages || _isSendingMessage) return;
    _cleanupTempStateCache();
    final queuedMessages = _messages
        .where((m) => m.id.startsWith('temp_') && _tempMessageStates[m.id] == _OutgoingUiState.queued)
        .toList();
    if (queuedMessages.isEmpty) return;

    _isRetryingQueuedMessages = true;
    try {
      for (final temp in queuedMessages) {
        if (!mounted) break;
        if (!_messages.any((m) => m.id == temp.id)) continue;
        setState(() => _tempMessageStates[temp.id] = _OutgoingUiState.sending);

        try {
          final draft = _pendingUploadDrafts[temp.id];
          final sent = draft != null
              ? await _sendPendingUploadDraft(draft)
              : await _messagesService.sendMessage(
                  widget.chatId,
                  temp.content,
                  imageUrl: temp.imageUrl,
                  originalImageUrl: temp.originalImageUrl,
                  fileUrl: temp.fileUrl,
                  fileName: temp.fileName,
                  fileSize: temp.fileSize,
                  fileMime: temp.fileMime,
                  replyToMessageId: temp.replyToMessageId,
                );

          if (!mounted) break;
          if (sent == null) {
            setState(() => _tempMessageStates[temp.id] = _OutgoingUiState.queued);
            continue;
          }

          setState(() {
            final idx = _messages.indexWhere((m) => m.id == temp.id);
            final newMessages = List<Message>.from(_messages);
            if (idx != -1) {
              newMessages[idx] = sent;
            } else {
              newMessages.add(sent);
            }
            _messages = newMessages;
            _tempMessageStates.remove(temp.id);
            _pendingUploadDrafts.remove(temp.id);
            unawaited(LocalMessagesService.removePendingUploadDraft(widget.chatId, temp.id));
            _cleanupTempStateCache();
          });
        } catch (e) {
          final isE2eeKeyError = e.toString().contains('E2EE ключ для чата пока недоступен');
          if (isE2eeKeyError) {
            unawaited(_ensureE2eeKeyAndReloadIfMissing(widget.chatId.toString()));
          }
          final shouldStayQueued = isE2eeKeyError || _isQueueableSendError(e);
          if (!mounted) break;
          setState(() {
            _tempMessageStates[temp.id] =
                shouldStayQueued ? _OutgoingUiState.queued : _OutgoingUiState.error;
          });
        }
      }
    } finally {
      _isRetryingQueuedMessages = false;
      if (mounted) {
        setState(() {
          _cleanupTempStateCache();
        });
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

  String _sanitizeFileName(String input) {
    final sanitized = input
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    if (sanitized.isEmpty) return 'chat';
    return sanitized.length > 60 ? sanitized.substring(0, 60) : sanitized;
  }

  String _formatExportTime(String createdAt) {
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(createdAt).toLocal());
    } catch (_) {
      return createdAt;
    }
  }

  Future<List<Message>> _collectMessagesForExport() async {
    final mergedById = <String, Message>{for (final m in _messages) m.id: m};
    var offset = 0;
    var hasMore = true;
    var safety = 0;

    while (hasMore && safety < 200) {
      final page = await _messagesService.fetchMessagesPaginated(
        widget.chatId,
        limit: 100,
        offset: offset,
        useCache: true,
      );
      for (final m in page.messages) {
        mergedById[m.id] = m;
      }
      if (page.messages.isEmpty) break;
      hasMore = page.hasMore;
      offset += page.messages.length;
      safety++;
    }

    final result = mergedById.values.toList();
    result.sort((a, b) {
      final ta = DateTime.tryParse(a.createdAt);
      final tb = DateTime.tryParse(b.createdAt);
      if (ta == null && tb == null) return a.id.compareTo(b.id);
      if (ta == null) return -1;
      if (tb == null) return 1;
      return ta.compareTo(tb);
    });
    return result;
  }

  String _buildChatExportText(List<Message> messages) {
    final now = DateTime.now();
    final buffer = StringBuffer()
      ..writeln('Chat export')
      ..writeln('Chat: ${widget.chatName}')
      ..writeln('Chat ID: ${widget.chatId}')
      ..writeln('Exported at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}')
      ..writeln('Total messages: ${messages.length}')
      ..writeln('---');

    for (final m in messages) {
      final parts = <String>[];
      final text = m.content.trim();
      if (text.isNotEmpty) parts.add(text);
      if (m.hasImage) parts.add('[image] ${m.imageUrl}');
      if (m.hasFile) {
        final fileLabel = (m.fileName != null && m.fileName!.trim().isNotEmpty) ? m.fileName!.trim() : 'file';
        parts.add('[file] $fileLabel ${m.fileUrl}');
      }
      if (parts.isEmpty) parts.add('[empty message]');

      final line = '[${_formatExportTime(m.createdAt)}] ${m.senderEmail}: ${parts.join(' | ')}';
      buffer.writeln(line);
    }

    return buffer.toString();
  }

  Future<void> _exportChat() async {
    if (_isExportingChat) return;
    setState(() => _isExportingChat = true);
    try {
      final messages = await _collectMessagesForExport();
      final text = _buildChatExportText(messages);
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = '${_sanitizeFileName(widget.chatName)}_$timestamp.txt';

      final okWeb = await downloadTextFile(
        filename: fileName,
        content: text,
        mimeType: 'text/plain; charset=utf-8',
      );
      if (okWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('Экспорт чата начат'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(text, flush: true);
      if (!mounted) return;

      final uri = Uri.file(file.path);
      final canOpen = await canLaunchUrl(uri);
      if (canOpen) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Экспорт сохранен: ${file.path}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('Не удалось экспортировать чат: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingChat = false);
      }
    }
  }

  Future<void> _retryErroredMessages() async {
    if (!mounted) return;
    setState(() {
      for (final entry in _tempMessageStates.entries.toList()) {
        if (entry.value == _OutgoingUiState.error) {
          _tempMessageStates[entry.key] = _OutgoingUiState.queued;
        }
      }
    });
    await _retryQueuedMessages();
  }

  Future<void> _clearPendingQueue() async {
    if (!mounted) return;
    final tempIds = _messages
        .where((m) => m.id.startsWith('temp_'))
        .map((m) => m.id)
        .toSet();
    if (tempIds.isEmpty) return;

    setState(() {
      _messages = _messages.where((m) => !tempIds.contains(m.id)).toList();
      for (final id in tempIds) {
        _tempMessageStates.remove(id);
        _pendingUploadDrafts.remove(id);
      }
    });
    await LocalMessagesService.clearPendingUploadDrafts(widget.chatId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Очередь отправки очищена'),
      ),
    );
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source);
      if (picked == null) return;

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return;
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageName = picked.name;
          _selectedImagePath = null;
          _selectedFilePath = null;
          _selectedFileBytes = null;
          _selectedFileName = null;
          _selectedFileSize = null;
        });
      } else {
        setState(() {
          _selectedImagePath = picked.path;
          _selectedImageBytes = null;
          _selectedImageName = picked.name;
          _selectedFilePath = null;
          _selectedFileBytes = null;
          _selectedFileName = null;
          _selectedFileSize = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка выбора изображения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    await _pickImageFromSource(ImageSource.gallery);
  }

  Future<void> _pickImageFromCamera() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Съемка с камеры недоступна в веб-версии'),
        ),
      );
      return;
    }
    await _pickImageFromSource(ImageSource.camera);
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
        const SnackBar(duration: Duration(seconds: 3), content: Text('Не удалось выбрать файл')),
      );
    }
  }

  /// Обработка перетаскивания файлов (drag-and-drop). Вызывается только onDragDone — без оверлея, чтобы не перекрывать чат.
  Future<void> _handleFilesDropped(DropDoneDetails details) async {
    if (_isRecordingVoice || _isUploadingImage || _isUploadingFile) return;
    final items = details.files;
    if (items.isEmpty) return;
    final DropItem fileItem = items.firstWhere(
      (item) => item is! DropItemDirectory,
      orElse: () => items.first,
    );
    if (fileItem is DropItemDirectory) return;
    try {
      final bytes = await fileItem.readAsBytes();
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
          SnackBar(duration: const Duration(seconds: 3), content: Text('Файл добавлен: $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
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
      if (kDebugMode) print('📦 Сжатие изображения: ${imageBytes.length} → ${compressedBytes.length} байт ($savedPercent% меньше, ${originalImage.width}x${originalImage.height} → ${newWidth}x$newHeight)');
      
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
            const SnackBar(
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка скачивания: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        const SnackBar(duration: Duration(seconds: 3), content: Text('Голосовые сообщения пока не поддерживаются в веб-версии')),
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
        const SnackBar(duration: Duration(seconds: 3), content: Text('Сначала отправьте/уберите вложение, затем запишите голосовое')),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    final hasPermission = await _voiceRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Нет доступа к микрофону. Разрешите доступ в настройках.')),
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
        const SnackBar(duration: Duration(seconds: 3), content: Text('Не удалось сохранить запись')),
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
        SnackBar(duration: const Duration(seconds: 3), content: Text('Ошибка записи: $e')),
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
        SnackBar(duration: const Duration(seconds: 3), content: Text('Не удалось воспроизвести аудио: ${e.toString().replaceFirst('Exception: ', '')}')),
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
    final trackInactive = isMine ? Colors.white.withValues(alpha: 0.35) : Colors.grey.shade300;
    final bubbleBg = isMine ? Colors.white.withValues(alpha: 0.22) : Colors.grey.shade50;
    final borderColor = isMine ? Colors.white.withValues(alpha: 0.35) : Colors.grey.shade200;
    final textColor = isMine ? Colors.white.withValues(alpha: 0.95) : AppColors.onSurfaceDark;
    final textSecondary = isMine ? Colors.white.withValues(alpha: 0.75) : AppColors.onSurfaceVariantDark;

    return Container(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bubbleBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isMine ? 0.08 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
          if (isMine)
            BoxShadow(
              color: (Theme.of(context).brightness == Brightness.dark ? _accent1 : AppColors.primary).withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isBusy)
            SizedBox(
              width: 48,
              height: 48,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(playColor),
                ),
              ),
            )
          else
            Material(
              color: isMine ? Colors.white.withValues(alpha: 0.28) : Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: isMine ? Colors.white.withValues(alpha: 0.4) : Colors.grey.shade200,
                  width: 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _toggleVoicePlayback(msg),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  child: Icon(
                    showPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 28,
                    color: playColor,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      size: 14,
                      color: textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Голосовое сообщение',
                      style: TextStyle(
                        fontSize: 11,
                        color: textSecondary,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(pos),
                      style: TextStyle(
                        fontSize: 13,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      dur == Duration.zero ? '—:—' : _formatDuration(dur),
                      style: TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
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
    if (_e2eeKeyState != _e2eeReady) {
      unawaited(_ensureE2eeKeyAndReloadIfMissing(widget.chatId.toString()));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Ключ шифрования ещё не готов. Подождите немного.'),
        ),
      );
      return;
    }
    
    final text = _controller.text.trim();
    final hasImage = _selectedImagePath != null || _selectedImageBytes != null;
    final hasFile = _selectedFilePath != null || _selectedFileBytes != null;
    // Сохраняем до любых сбросов/ошибок для возможности поставить в очередь.
    final replyToMessageId = _replyToMessage?.id;
    final replyToMessage = _replyToMessage;
    
    if (kDebugMode) print('🔍 Text: "$text", hasImage: $hasImage, hasFile: $hasFile');
    
    if (text.isEmpty && !hasImage && !hasFile) {
      if (kDebugMode) print('⚠️ Text is empty and no attachments, returning');
      return;
    }

    if (_isSendingMessage) return;
    _isSendingMessage = true;
    if (mounted) setState(() {});

    try {
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
        imageUrl = await _messagesService.uploadImage(
          bytes,
          fileName,
          originalBytes: originalBytes,
          chatId: widget.chatId.toString(),
        );
        
        // ✅ Очищаем память после успешной загрузки
        if (mounted) {
          setState(() {
            _selectedImagePath = null;
            _selectedImageBytes = null;
            _selectedImageName = null;
          });
        }
      } catch (e) {
        if (_isQueueableSendError(e)) {
          _enqueuePendingUploadDraft(
            _PendingUploadDraft(
              text: text,
              replyToMessageId: replyToMessageId,
              replyToMessage: replyToMessage,
              imageBytes: _selectedImageBytes,
              imagePath: _selectedImagePath,
              imageName: _selectedImageName,
            ),
          );
          return;
        }
        if (mounted) {
          setState(() => _isUploadingImage = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
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
            const SnackBar(duration: Duration(seconds: 3), content: Text('Нельзя отправить изображение и файл в одном сообщении')),
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
        if (_isQueueableSendError(e)) {
          _enqueuePendingUploadDraft(
            _PendingUploadDraft(
              text: text,
              replyToMessageId: replyToMessageId,
              replyToMessage: replyToMessage,
              fileBytes: _selectedFileBytes,
              filePath: _selectedFilePath,
              fileName: _selectedFileName,
              fileSize: _selectedFileSize,
              fileMime: _selectedFileName?.toLowerCase().endsWith('.m4a') == true
                  ? 'audio/mp4'
                  : null,
            ),
          );
          return;
        }
        if (mounted) {
          setState(() => _isUploadingFile = false);
          ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
            duration: const Duration(seconds: 3),
            content: Text('Ошибка загрузки файла: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
          );
        }
        return;
      }
      setState(() => _isUploadingFile = false);
    }

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
      senderAvatarUrl: widget.myAvatarUrl,
      createdAt: DateTime.now().toIso8601String(),
      isRead: false,
      replyToMessageId: replyToMessageId,
      replyToMessage: replyToMessage,
      keyVersion: 1,
    );
    
    // ✅ Добавляем сообщение оптимистично в список (без перезагрузки)
    // Сохраняем позицию скролла ДО добавления сообщения
    bool wasAtBottom = false;
    double? savedScrollPosition;
    if (mounted && _scrollController.hasClients) {
      final currentMaxScroll = _scrollController.position.maxScrollExtent;
      savedScrollPosition = _scrollController.position.pixels;
      if (currentMaxScroll > 0) {
        const threshold = 100.0; // Увеличиваем порог для более надежной проверки
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
        _tempMessageStates[tempMessageId] = _OutgoingUiState.sending;
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

              // ✅ Если WebSocket успел добавить это же сообщение раньше, убираем дубликаты по id.
              // Оставляем только ту запись, которую мы сейчас поставили на место tempIndex.
              final realId = sentMessage.id;
              for (int i = newMessages.length - 1; i >= 0; i--) {
                if (i == tempIndex) continue;
                if (newMessages[i].id == realId) {
                  newMessages.removeAt(i);
                }
              }
              _messages = newMessages;
              _tempMessageStates.remove(tempMessageId);
              _pendingUploadDrafts.remove(tempMessageId);
              unawaited(LocalMessagesService.removePendingUploadDraft(widget.chatId, tempMessageId));
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

                // ✅ Убираем возможные дубликаты по id (оставляем updated на existingIndex)
                final realId = sentMessage.id;
                for (int i = newMessages.length - 1; i >= 0; i--) {
                  if (i == existingIndex) continue;
                  if (newMessages[i].id == realId) {
                    newMessages.removeAt(i);
                  }
                }
                newMessages.removeWhere((m) => m.id == tempMessageId);
                
                _messages = newMessages;
                _tempMessageStates.remove(tempMessageId);
                _pendingUploadDrafts.remove(tempMessageId);
                unawaited(LocalMessagesService.removePendingUploadDraft(widget.chatId, tempMessageId));
              });
              if (kDebugMode) print('✅ Message updated in place at index $existingIndex');
            } else {
              if (kDebugMode) print('⚠️ Temp message not found and message not in list, adding it');
              setState(() {
                // ✅ Создаем новый список для принудительного обновления UI
                final newMessages = List<Message>.from(_messages);
                newMessages.add(sentMessage); // добавляем в конец, новые снизу

                // ✅ Убираем возможные дубликаты по id (если WS уже добавил)
                final realId = sentMessage.id;
                for (int i = newMessages.length - 2; i >= 0; i--) {
                  if (newMessages[i].id == realId) {
                    newMessages.removeAt(i);
                  }
                }
                newMessages.removeWhere((m) => m.id == tempMessageId);
                
                _messages = newMessages;
                _tempMessageStates.remove(tempMessageId);
                _pendingUploadDrafts.remove(tempMessageId);
                unawaited(LocalMessagesService.removePendingUploadDraft(widget.chatId, tempMessageId));
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
          
          // Кэш обновляется в MessagesService на raw-ответе сервера, чтобы не сохранять plaintext E2EE.
        } else {
          if (kDebugMode) print('⚠️ No message received from server response');
        }
        
        // ✅ Fallback: Если через 3 секунды временное сообщение все еще есть,
        // значит WebSocket не получил сообщение - оставляем как есть
        // (сообщение уже обновлено из ответа сервера выше)
        Future.delayed(const Duration(seconds: 3), () {
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
      final errorText = e.toString();
      final errorTextLower = errorText.toLowerCase();
      final isE2eeKeyError = errorText.contains('E2EE ключ для чата пока недоступен');
      final isQueueableNetworkError =
          errorTextLower.contains('нет подключения к интернету') ||
          errorTextLower.contains('socketexception') ||
          errorTextLower.contains('timeout') ||
          errorTextLower.contains('timed out') ||
          errorTextLower.contains('connection');
      if (isE2eeKeyError) {
        unawaited(_ensureE2eeKeyAndReloadIfMissing(widget.chatId.toString()));
      }
      
      if (mounted) {
        setState(() {
          _tempMessageStates[tempMessageId] =
              isQueueableNetworkError ? _OutgoingUiState.queued : _OutgoingUiState.error;
        });
        
        // Восстанавливаем поле ответа, если была ошибка
        if (_replyToMessage == null && tempMessage.replyToMessage != null) {
          setState(() {
            _replyToMessage = tempMessage.replyToMessage;
          });
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Text(
              isQueueableNetworkError
                  ? 'Нет сети: сообщение оставлено в очереди и будет отправлено при подключении.'
                  : isE2eeKeyError
                  ? 'Ожидаем ключ шифрования. Попробуйте отправить снова через пару секунд.'
                  : 'Ошибка отправки сообщения: ${networkErrorMessage(e)}',
            ),
          ),
        );
      }
    }
    } finally {
      _isSendingMessage = false;
      if (mounted) setState(() {});
    }
  }

  /// Установить сообщение как ответ и прокрутить к полю ввода (для свайпа «Ответить» и меню).
  void _setReplyAndScrollToInput(Message message) {
    setState(() {
      _replyToMessage = message;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: scheme.onSurface.withValues(alpha:0.85)),
                  const SizedBox(width: 8),
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
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.cardDark, AppColors.surfaceDark],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.borderDark),
              boxShadow: AppColors.neonGlowSoft,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
                const SizedBox(height: 12),
                Divider(height: 1, color: scheme.outline.withValues(alpha: 0.20)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    message.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    color: scheme.onSurface.withValues(alpha:0.85),
                  ),
                  title: Text(message.isPinned ? 'Открепить' : 'Закрепить'),
                  onTap: () => Navigator.pop(context, message.isPinned ? 'unpin' : 'pin'),
                ),
                if (!isMine) ...[
                  Divider(height: 1, color: scheme.outline.withValues(alpha: 0.20)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.flag_outlined, color: scheme.onSurface.withValues(alpha: 0.85)),
                    title: const Text('Пожаловаться'),
                    onTap: () => Navigator.pop(context, 'report'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.block_rounded, color: Colors.orange.shade700),
                    title: Text('Заблокировать пользователя', style: TextStyle(color: Colors.orange.shade700)),
                    onTap: () => Navigator.pop(context, 'block'),
                  ),
                ],
                if (isMine) ...[
                  Divider(height: 1, color: scheme.outline.withValues(alpha: 0.20)),
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
      _setReplyAndScrollToInput(message);
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
    } else if (action == 'report') {
      _reportMessage(message);
    } else if (action == 'block') {
      _blockSender(message);
    }
  }

  final ModerationService _moderationService = ModerationService();

  Future<void> _reportMessage(Message message) async {
    try {
      await _moderationService.reportMessage(message.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: Duration(seconds: 3), content: Text('Жалоба отправлена. Модерация рассмотрит в течение 24 часов.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _blockSender(Message message) async {
    if (message.userId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заблокировать пользователя?'),
        content: Text(
          'Сообщения от ${message.senderEmail} будут скрыты. Вы сможете разблокировать через настройки.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _moderationService.blockUser(message.userId);
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.userId == message.userId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: Duration(seconds: 3), content: Text('Пользователь заблокирован. Его сообщения скрыты.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }
  
  // ✅ Диалог пересылки сообщения
  Future<void> _showForwardDialog(Message message) async {
    if (!mounted) return;
    
    // Загружаем список чатов пользователя
    final chats = await _chatsService.fetchChats(widget.userId);
    if (!mounted) return;
    final availableChats = chats.where((chat) => chat.id != widget.chatId).toList();
    
    if (availableChats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Нет других чатов для пересылки')),
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
              title: const Text('Переслать сообщение'),
              content: Container(
                width: double.maxFinite,
                constraints: const BoxConstraints(maxHeight: 400),
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
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: selectedChatIds.isEmpty
                      ? null
                      : () {
                          Navigator.pop(context, selectedChatIds.toList());
                        },
                  child: const Text('Переслать'),
                ),
              ],
            );
          },
        );
      },
    );
    
    if (selectedChats != null && selectedChats.isNotEmpty) {
      try {
        await _messagesService.forwardMessage(message, widget.chatId.toString(), selectedChats);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(duration: const Duration(seconds: 3), content: Text('Сообщение переслано в ${selectedChats.length} чат(ов)')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(duration: const Duration(seconds: 3), content: Text('Ошибка пересылки: $e')),
          );
        }
      }
    }
  }
  
  // ✅ Закрепить сообщение
  Future<void> _pinMessage(Message message) async {
    try {
      await _messagesService.pinMessage(message.id);
      if (!mounted) return;
      await _loadPinnedMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Сообщение закреплено')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Ошибка закрепления: $e')),
        );
      }
    }
  }
  
  // ✅ Открепить сообщение
  Future<void> _unpinMessage(Message message) async {
    try {
      await _messagesService.unpinMessage(message.id);
      if (!mounted) return;
      await _loadPinnedMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: Duration(seconds: 3), content: Text('Сообщение откреплено')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 3), content: Text('Ошибка открепления: $e')),
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
          padding: const EdgeInsets.all(16),
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
            SnackBar(duration: const Duration(seconds: 3), content: Text('Ошибка: $e')),
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
            style: const TextStyle(fontSize: 24),
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
        title: const Text('Редактировать сообщение'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Введите текст сообщения',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final newContent = textController.text.trim();
              if (newContent.isNotEmpty) {
                Navigator.pop(context, {'content': newContent});
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    
    if (result != null && result['content'] != null) {
      try {
        await _messagesService.editMessage(
          message.id,
          content: result['content']!,
          chatId: widget.chatId.toString(),
        );
        if (mounted) {
          setState(() {
            final index = _messages.indexWhere((m) => m.id == message.id);
            if (index != -1) {
              final prev = _messages[index];
              _messages[index] = Message(
                id: prev.id,
                chatId: prev.chatId,
                userId: prev.userId,
                content: result['content']!,
                imageUrl: prev.imageUrl,
                originalImageUrl: prev.originalImageUrl,
                fileUrl: prev.fileUrl,
                fileName: prev.fileName,
                fileSize: prev.fileSize,
                fileMime: prev.fileMime,
                messageType: prev.messageType,
                senderEmail: prev.senderEmail,
                senderAvatarUrl: prev.senderAvatarUrl,
                createdAt: prev.createdAt,
                deliveredAt: prev.deliveredAt,
                editedAt: DateTime.now().toIso8601String(),
                isRead: prev.isRead,
                readAt: prev.readAt,
                replyToMessageId: prev.replyToMessageId,
                replyToMessage: prev.replyToMessage,
                isPinned: prev.isPinned,
                reactions: prev.reactions,
                isForwarded: prev.isForwarded,
                originalChatName: prev.originalChatName,
                keyVersion: prev.keyVersion,
              );
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(duration: const Duration(seconds: 3), content: Text('Ошибка редактирования сообщения: $e')),
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
        title: const Text('Удалить сообщение?'),
        content: const Text('Вы уверены, что хотите удалить это сообщение?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _messagesService.deleteMessage(message.id.toString(), widget.userId);
      await LocalMessagesService.removeMessage(widget.chatId, message.id);
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == message.id);
          _pinnedMessages.removeWhere((m) => m.id == message.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сообщение удалено'),
            duration: Duration(seconds: 2),
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
        title: const Text('Очистить чат?'),
        content: const Text('Вы уверены, что хотите удалить все сообщения из этого чата? Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _messagesService.clearChat(widget.chatId, widget.userId);
      await LocalMessagesService.clearChat(widget.chatId);
      if (mounted) {
        setState(() {
          _messages.clear();
          _pinnedMessages.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Чат успешно очищен'),
            duration: Duration(seconds: 2),
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
    PushNotificationService.setCurrentChatId(null);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _webSocketSubscription?.cancel();
    _typingStopTimer?.cancel();
    _typingCleanupTimer?.cancel();
    _pollTimer?.cancel();
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
        title: const Text('Выйти из чата?'),
        content: Text('Вы уверены, что хотите выйти из чата "${widget.chatName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _chatsService.leaveChat(widget.chatId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вы вышли из чата'),
            duration: Duration(seconds: 2),
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
            const SnackBar(duration: Duration(seconds: 3), content: Text('Нет доступных пользователей для добавления')),
          );
        }
        return;
      }
      
      if (!mounted) return;
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
          // E2EE: отправить ключ чата новым участникам (как при входе по инвайту)
          E2eeService.shareChatKeyWithNewMembers(widget.chatId.toString());
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Участники успешно добавлены'),
                duration: Duration(seconds: 2),
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

  void _openUserProfile(Message msg) {
    final otherId = msg.userId.toString().trim();
    if (otherId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: otherId,
          fallbackLabel: msg.senderEmail,
        ),
      ),
    );
  }

  void _openImageViewer(Message msg) {
    final url = (msg.imageUrl ?? '').trim();
    if (url.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => _FullScreenImageViewer(
          imageUrl: url,
          chatId: widget.chatId.toString(),
          originalImageUrl: (msg.originalImageUrl ?? url),
          fileName: url.split('/').last.isNotEmpty ? url.split('/').last : 'image.jpg',
          onDownload: () => _downloadImage(
            (msg.originalImageUrl ?? url),
            url.split('/').last.isNotEmpty ? url.split('/').last : 'image.jpg',
          ),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  // ✅ Вычисляем высоту блока закрепленных сообщений
  double _getPinnedMessagesHeight() {
    if (_pinnedMessages.isEmpty) return 0.0;
    // Компактные размеры
    const headerHeight = 28.0; // Компактный заголовок
    const messageHeight = 32.0; // Компактная высота одного сообщения
    final messagesCount = _pinnedMessages.length > 3 ? 3 : _pinnedMessages.length;
    const padding = 12.0; // Внутренние отступы
    const margin = 8.0; // Внешние отступы
    return headerHeight + (messagesCount * messageHeight) + padding + margin;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pinnedHeight = _getPinnedMessagesHeight();
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
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
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha:0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.search_rounded, color: _accent1),
              onPressed: _openSearch,
              tooltip: 'Поиск по сообщениям',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha:0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.people_rounded, color: _accent1),
              onPressed: _showMembersDialog,
              tooltip: 'Участники чата',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_accent1, _accent2]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _accent1.withValues(alpha:0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: widget.isGroup
                ? IconButton(
                    icon: const Icon(Icons.person_add_rounded, color: Colors.white),
                    onPressed: _showAddMembersDialog,
                    tooltip: 'Добавить участников',
                  )
                : const SizedBox.shrink(),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: scheme.onSurface.withValues(alpha:0.75)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'gallery') _openGallery();
              if (value == 'export') _exportChat();
              if (value == 'mentions') _openMentions();
              if (value == 'clear') _clearChat();
              if (value == 'leave') _leaveChat();
              if (value == 'invite' && widget.isGroup) _showInviteDialog();
              if (value == 'rename' && widget.isGroup) _renameGroupChatDialog();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'gallery',
                child: Row(
                  children: [
                    Icon(Icons.photo_library_rounded, color: Colors.purple.shade300, size: 20),
                    const SizedBox(width: 10),
                    const Text('Медиа'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export',
                enabled: !_isExportingChat,
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, color: Colors.teal.shade600, size: 20),
                    const SizedBox(width: 10),
                    Text(_isExportingChat ? 'Экспорт...' : 'Экспорт чата'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'mentions',
                child: Row(
                  children: [
                    Icon(Icons.alternate_email_rounded, color: Colors.blue.shade300, size: 20),
                    const SizedBox(width: 10),
                    const Text('Упоминания'),
                  ],
                ),
              ),
              if (widget.isGroup)
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_rounded, color: Colors.blueGrey.shade700, size: 20),
                      const SizedBox(width: 10),
                      const Text('Переименовать'),
                    ],
                  ),
                ),
              if (widget.isGroup)
                PopupMenuItem(
                  value: 'invite',
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 10),
                      const Text('Пригласить (код)'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_rounded, color: Colors.red.shade400, size: 20),
                    const SizedBox(width: 10),
                    const Text('Очистить чат'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app_rounded, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 10),
                    const Text('Выйти из чата'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Material(
        color: scaffoldBg,
        child: DropTarget(
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
                        const CircularProgressIndicator(
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
                    ? const ChatEmptyMessages(accentColor: _accent1)
                    : RepaintBoundary(
                  child: Stack(
                    children: [
                      // Отступ сверху для закрепленных сообщений
                      Padding(
                        padding: EdgeInsets.only(
                          top: pinnedHeight,
                        ),
                        child: RefreshIndicator(
                          onRefresh: () async {
                            await _loadMessages();
                          },
                          color: _accent1,
                          child: ListView.builder(
                            key: ValueKey('messages_list_${widget.chatId}'),
                            controller: _scrollController,
                            reverse: false, // старые сверху, новые снизу
                            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                            cacheExtent: 800, // Предзагрузка элементов для плавного скролла
                            addAutomaticKeepAlives: false, // Меньше памяти при длинных списках
                            itemCount: _listEntries.length,
                        itemBuilder: (context, index) {
                          final entry = _listEntries[index];
                          if (entry is _LoadMoreEntry) {
                            return ChatLoadMoreButton(
                              onPressed: _loadMoreMessages,
                              accentColor: _accent1,
                            );
                          }
                          if (entry is _LoadingEntry) {
                            return const ChatLoadingRow(accentColor: _accent1);
                          }
                          if (entry is _DateHeaderEntry) {
                            return ChatDateHeader(label: entry.label, accentColor: _accent1);
                          }
                          final msg = _messages[(entry as _MessageEntry).index];
                    final isMine = msg.userId == widget.userId;

                final isHighlighted = _highlightMessageId == msg.id;
                return FadeScaleIn(
                  key: ValueKey('fade_${msg.id}'),
                  child: Slidable(
                  key: _keyForMessage(msg.id),
                  startActionPane: ActionPane(
                    motion: const ScrollMotion(),
                    extentRatio: 0.22,
                    children: [
                      SlidableAction(
                        onPressed: (_) => _setReplyAndScrollToInput(msg),
                        backgroundColor: _accent1.withValues(alpha: 0.85),
                        foregroundColor: Colors.white,
                        icon: Icons.reply_rounded,
                        label: 'Ответить',
                      ),
                    ],
                  ),
                  endActionPane: isMine
                      ? ActionPane(
                          motion: const ScrollMotion(),
                          extentRatio: 0.22,
                          children: [
                            SlidableAction(
                              onPressed: (_) => _showDeleteMessageDialog(msg),
                              backgroundColor: Colors.red.shade400,
                              foregroundColor: Colors.white,
                              icon: Icons.delete_outline_rounded,
                              label: 'Удалить',
                            ),
                          ],
                        )
                      : null,
                  child: ChatMessageTile(
                  key: ValueKey('tile_${msg.id}'),
                  msg: msg,
                  isMine: isMine,
                  isHighlighted: isHighlighted,
                  scheme: scheme,
                  accent1: _accent1,
                  accent2: _accent2,
                  accent3: _accent3,
                  myUserId: widget.userId,
                  myAvatarUrl: widget.myAvatarUrl,
                  chatId: widget.chatId.toString(),
                  myAvatarPlaceholder: _myAvatarPlaceholder(),
                  otherAvatarPlaceholder: _otherAvatarPlaceholder(msg.senderEmail),
                  memberByHandle: _memberByHandle,
                  onOpenSenderProfile: () => _openUserProfile(msg),
                  onShowMessageMenu: () => _showMessageMenu(msg, isMine: isMine),
                  onOpenImage: () => _openImageViewer(msg),
                  buildVoiceBubble: () => _buildVoiceBubble(msg, isMine: isMine),
                  isVoiceMessage: () => _isVoiceMessage(msg),
                  formatBytes: _formatBytes,
                  formatDate: _formatDate,
                  buildMessageStatus: _buildMessageStatus(msg),
                  onShowReactionPicker: () => _showReactionPicker(msg),
                  onOpenUserProfileById: (uid, label) => _openUserProfileById(uid, fallbackLabel: label),
                ),
                ),
                );
                        },
                          ),
                        ),
                      ),
                      // ✅ Закрепленные сообщения - всегда видны вверху
                      if (_pinnedMessages.isNotEmpty)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Компактный заголовок
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.push_pin,
                                        size: 12,
                                        color: _accent1.withValues(alpha:0.8),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Закреплено',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _accent1.withValues(alpha:0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${_pinnedMessages.length}',
                                          style: const TextStyle(
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
                                  padding: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
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
                                                  duration: const Duration(milliseconds: 300),
                                                  curve: Curves.easeInOut,
                                                );
                                              }
                                            },
                                            borderRadius: BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: scheme.outline.withValues(alpha: 0.18),
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
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      pinned.content.isNotEmpty 
                                                          ? (pinned.content.length > 40 
                                                              ? '${pinned.content.substring(0, 40)}...'
                                                              : pinned.content)
                                                          : 'Фото',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w400,
                                                        color: AppColors.onSurfaceVariantDark,
                                                        height: 1.2,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    Icons.chevron_right,
                                                    size: 16,
                                                    color: AppColors.onSurfaceVariantDark.withValues(alpha: 0.8),
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
              border: Border(top: BorderSide(color: AppColors.borderDark.withValues(alpha: 0.5))),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ✅ Индикатор очереди офлайн: сообщения будут отправлены при подключении
                    if (_messages.any((m) => m.id.startsWith('temp_')))
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha:0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withValues(alpha:0.35)),
                        ),
                        child: Builder(
                          builder: (context) {
                            final tempMessages = _messages.where((m) => m.id.startsWith('temp_')).toList();
                            final queued = tempMessages
                                .where((m) => _tempMessageStates[m.id] == _OutgoingUiState.queued)
                                .length;
                            final errors = tempMessages
                                .where((m) => _tempMessageStates[m.id] == _OutgoingUiState.error)
                                .length;
                            final sending = tempMessages.length - queued - errors;
                            final parts = <String>[];
                            if (queued > 0) parts.add('в очереди: $queued');
                            if (sending > 0) parts.add('отправляется: $sending');
                            if (errors > 0) parts.add('ошибка: $errors');
                            final details = parts.isEmpty ? 'сообщений: ${tempMessages.length}' : parts.join(', ');

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.cloud_off_rounded, size: 18, color: Colors.orange.shade700),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Черновики отправки — $details',
                                        style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: errors > 0 ? _retryErroredMessages : null,
                                      icon: const Icon(Icons.refresh_rounded, size: 16),
                                      label: const Text('Повторить ошибки'),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      onPressed: tempMessages.isNotEmpty ? _clearPendingQueue : null,
                                      icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                                      label: const Text('Очистить очередь'),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    // ✅ Превью ответа на сообщение
                    if (_replyToMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _accent1.withValues(alpha:0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: const Border(
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
                                  const Text(
                                    'Ответ на сообщение',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _accent1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (_replyToMessage!.hasFile)
                                    Row(
                                      children: [
                                        Icon(Icons.insert_drive_file_rounded, size: 14, color: Colors.grey.shade600),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            decodeFileNameForDisplay(_replyToMessage!.fileName),
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
                                        const SizedBox(width: 4),
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
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                setState(() {
                                  _replyToMessage = null;
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    // Превью выбранного изображения
                    if (_selectedImagePath != null || _selectedImageBytes != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
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
                                      : const SizedBox.shrink(),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () {
                                  setState(() {
                                    _selectedImagePath = null;
                                    _selectedImageBytes = null;
                                    _selectedImageName = null;
                                  });
                                },
                                iconSize: 20,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
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
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.insert_drive_file_rounded, color: _accent2),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedFileName ?? 'Файл',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
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
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                setState(() {
                                  _selectedFilePath = null;
                                  _selectedFileBytes = null;
                                  _selectedFileName = null;
                                  _selectedFileSize = null;
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    if (_e2eeStatusText() != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          _e2eeStatusText()!,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    // ✅ Индикатор записи голосового
                    ChatInputBar(
                      scheme: scheme,
                      accent1: _accent1,
                      accent2: _accent2,
                      controller: _controller,
                      isUploadingImage: _isUploadingImage,
                      isUploadingFile: _isUploadingFile,
                      isSendingMessage: _isSendingMessage,
                      isRecordingVoice: _isRecordingVoice,
                      voiceRecordDuration: _voiceRecordDuration,
                      onCancelVoiceRecording: _cancelVoiceRecording,
                      onPickFile: _pickFile,
                      onPickImage: _pickImage,
                      onPickCamera: _pickImageFromCamera,
                      onToggleVoiceRecording: _toggleVoiceRecording,
                      onVoiceLongPressStart: _startVoiceRecordingIfNotRecording,
                      onVoiceLongPressEnd: _stopAndSendVoiceRecordingIfRecording,
                      onSend: _sendMessage,
                      onChanged: _handleComposerChanged,
                      mentionSuggestions: _mentionSuggestions,
                      onSelectMention: _insertMention,
                    ),
                  ],
                ),
              ),
            ),
          ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Полноэкранный просмотр фото в стиле Telegram/WhatsApp: тёмный фон, зум, тап — закрыть.
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String? chatId;
  final String? originalImageUrl;
  final String fileName;
  final VoidCallback? onDownload;

  const _FullScreenImageViewer({
    required this.imageUrl,
    this.chatId,
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
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: E2eeImage(
                  imageUrl: imageUrl,
                  chatId: chatId,
                  fit: BoxFit.contain,
                  memCacheWidth: 1920,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white70,
                      strokeWidth: 2,
                    ),
                  ),
                  errorWidget: (_, __, ___) => const Center(
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Material(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
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
                        child: const Padding(
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
