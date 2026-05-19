import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'package:http/http.dart' show ClientException;

import '../models/message.dart';
import '../services/messages_service.dart';
import '../services/chats_service.dart';
import '../services/moderation_service.dart';
import '../services/local_messages_service.dart'; // ✅ Импорт сервиса кэширования
import '../services/notification_feedback_service.dart';
import '../services/push_notification_service.dart';
import '../services/websocket_service.dart';
import '../services/voice_call_service.dart';
import '../services/e2ee_service.dart';
import '../theme/app_colors.dart';
import '../utils/file_name_display.dart';
import '../utils/network_error_helper.dart';
import '../utils/download_text_file.dart';
import '../utils/voice_message_utils.dart';
import '../widgets/chat_date_header.dart';
import '../widgets/chat_empty_messages.dart';
import '../widgets/chat_load_more_button.dart';
import '../widgets/chat_loading_row.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_message_tile.dart';
import '../widgets/fade_scale_in.dart';
import 'add_members_dialog.dart';
import 'chat_members_dialog.dart';
import 'chat_gallery_screen.dart';
import 'video_player_screen.dart';
import 'user_profile_screen.dart';
import '../widgets/chat_fullscreen_image_viewer.dart';
import '../widgets/chat_voice_bubble.dart';
import '../features/chat/chat_scroll_policy.dart';
import '../features/chat/chat_sync_policy.dart';

part 'chat_screen_models.dart';
part 'chat_screen_export.dart';
part 'chat_screen_media_voice.dart';
part 'chat_screen_members.dart';
part 'chat_screen_queue.dart';
part 'chat_screen_message_actions.dart';
part 'chat_screen_scroll.dart';
part 'chat_screen_search.dart';
part 'chat_screen_websocket.dart';
part 'chat_screen_typing_composer.dart';
part 'chat_screen_messages_sync.dart';
part 'chat_screen_send.dart';
part 'chat_screen_voice_call.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String? displayName;
  final String? myAvatarUrl;
  final String chatId;
  final String chatName;
  final bool isGroup;

  const ChatScreen({
    super.key,
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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const String _e2eeReady = 'ready';
  static const String _e2eeMissing = 'missing';
  static const String _e2eeRequesting = 'requesting';
  static const String _e2eeRetryBackoff = 'retryBackoff';
  static const String _e2eeFailed = 'failed';

  static Color get _accent1 => AppColors.primary;
  static Color get _accent2 => AppColors.primaryGlow;
  static Color get _accent3 => AppColors.accent;

  Widget _myAvatarPlaceholder() {
    final initial = widget.userEmail.isNotEmpty
        ? widget.userEmail[0].toUpperCase()
        : '?';
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent1, _accent2],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _otherAvatarPlaceholder(String senderEmail) {
    final initial = senderEmail.trim().isNotEmpty
        ? senderEmail.trim()[0].toUpperCase()
        : '?';
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent3, _accent2],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messagesService = MessagesService();
  final _chatsService = ChatsService();
  final ModerationService _moderationService = ModerationService();
  StreamSubscription? _webSocketSubscription;
  DateTime? _lastWsReconnectHandledAt;
  final Map<String, GlobalKey> _messageKeys = {};

  List<Message> _messages = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _didInitialOpenScrollToBottom = false;
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
  final Map<String, String> _tempMessageIdempotencyKeys = {};
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
  final Map<String, Map<String, String>> _memberByHandle =
      {}; // handle -> {id,email,label}
  final Set<String> _onlineUserIds = <String>{};
  final Map<String, DateTime> _typingUntilByUserId = <String, DateTime>{};
  Timer? _typingStopTimer;
  Timer? _typingCleanupTimer;
  bool _sentTyping = false;
  bool _subscribedToChatRealtime = false;
  Timer?
  _pollTimer; // резервный опрос новых сообщений при проблемах с WebSocket
  late String _chatTitle;

  // ✅ Mentions (@handle)
  int _mentionStart = -1;
  String _mentionQuery = '';
  List<Map<String, String>> _mentionSuggestions = [];

  List<_ListEntry>? _cachedListEntries;
  int _listEntriesCacheKey = -1;

  Widget? _cachedMyAvatarPlaceholder;
  final Map<String, Widget> _otherAvatarPlaceholderBySender = {};
  final Set<String> _messageIdsWithoutFade = {};
  static const int _maxCachedOtherAvatars = 64;

  Widget get _myAvatarPlaceholderWidget {
    return _cachedMyAvatarPlaceholder ??= _myAvatarPlaceholder();
  }

  Widget _otherAvatarWidget(String senderEmail) {
    final key = senderEmail.trim();
    final hit = _otherAvatarPlaceholderBySender[key];
    if (hit != null) return hit;
    final widget = _otherAvatarPlaceholder(key);
    if (_otherAvatarPlaceholderBySender.length >= _maxCachedOtherAvatars) {
      _otherAvatarPlaceholderBySender.remove(
        _otherAvatarPlaceholderBySender.keys.first,
      );
    }
    _otherAvatarPlaceholderBySender[key] = widget;
    return widget;
  }

  void _markMessagesSeen(Iterable<String> ids) {
    _messageIdsWithoutFade.addAll(ids);
  }

  bool _shouldFadeInMessage(String id) => !_messageIdsWithoutFade.contains(id);

  List<_ListEntry> get _listEntries {
    final len = _messages.length;
    final key =
        len ^
        (_hasMoreMessages ? 0x10000 : 0) ^
        (_isLoadingMore ? 0x20000 : 0) ^
        (len > 0 ? _messages.first.id.hashCode : 0) ^
        (len > 0 ? _messages.last.id.hashCode : 0);
    if (_cachedListEntries != null && _listEntriesCacheKey == key) {
      return _cachedListEntries!;
    }
    _listEntriesCacheKey = key;
    final list = <_ListEntry>[];
    if (_hasMoreMessages && !_isLoadingMore && _messages.isNotEmpty)
      list.add(_LoadMoreEntry());
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
                              const SnackBar(
                                duration: Duration(seconds: 3),
                                content: Text('Код скопирован'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Передайте этот код человеку — он введёт его в “Вступить по коду”.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
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
                  onPressed: isLoading
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Закрыть'),
                ),
                if (code == null || code.isEmpty)
                  ElevatedButton(
                    onPressed: isLoading ? null : create,
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
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
                final updated = await _chatsService.renameChat(
                  widget.chatId,
                  name,
                );
                final newName = (updated['name'] ?? name).toString();
                if (!mounted) return;
                setState(() => _chatTitle = newName);
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(
                    duration: Duration(seconds: 3),
                    content: Text('Название обновлено'),
                  ),
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
                  onPressed: isLoading
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : save,
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
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
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(WebSocketService.instance.connectIfNeeded());
    unawaited(_retryQueuedMessages());
    unawaited(_pollForNewMessages());
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
      final shouldKeepAtBottom = _isNearBottom();
      setState(() {
        _messages = List<Message>.from(_messages)..addAll(toAdd);
      });
      if (fromOthers) NotificationFeedbackService.onNewMessage();
      if (shouldKeepAtBottom) _scrollToBottom();
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
          ..addEntries(
            members
                .map((m) {
                  final id = (m['id'] ?? '').toString();
                  final email = (m['email'] ?? '').toString();
                  return MapEntry(id, email);
                })
                .where((e) => e.key.isNotEmpty),
          );

        _memberByHandle
          ..clear()
          ..addEntries(
            members
                .map((m) {
                  final id = (m['id'] ?? '').toString();
                  final email = (m['email'] ?? '').toString();
                  final label = (m['displayName'] ?? m['display_name'] ?? email)
                      .toString();
                  final handle = _handleFromEmail(email);
                  return MapEntry(handle, {
                    'id': id,
                    'email': email,
                    'label': label,
                  });
                })
                .where(
                  (e) => e.key.isNotEmpty && (e.value['id'] ?? '').isNotEmpty,
                ),
          );
      });
    } catch (e) {
      // Не критично — presence/typing просто будет без имён
      if (kDebugMode)
        print('Ошибка загрузки участников (для presence/typing): $e');
    }
  }

  GlobalKey _keyForMessage(String id) {
    return _messageKeys.putIfAbsent(id, () => GlobalKey());
  }

  /// Сливает пришедшее по WebSocket сообщение с уже имеющимся: не затираем непустой контент пустым
  /// (на части устройств/сетей WS может прийти с пустым content).
  Message _mergeMessageKeepContent(Message existing, Message incoming) {
    if (incoming.content.isNotEmpty ||
        (incoming.imageUrl ?? '').isNotEmpty ||
        (incoming.fileUrl ?? '').isNotEmpty)
      return incoming;
    return Message(
      id: incoming.id,
      chatId: incoming.chatId,
      userId: incoming.userId,
      content: incoming.content.isNotEmpty
          ? incoming.content
          : existing.content,
      imageUrl: (incoming.imageUrl ?? '').isNotEmpty
          ? incoming.imageUrl
          : existing.imageUrl,
      originalImageUrl: (incoming.originalImageUrl ?? '').isNotEmpty
          ? incoming.originalImageUrl
          : existing.originalImageUrl,
      fileUrl: (incoming.fileUrl ?? '').isNotEmpty
          ? incoming.fileUrl
          : existing.fileUrl,
      fileName: incoming.fileName ?? existing.fileName,
      fileSize: incoming.fileSize ?? existing.fileSize,
      fileMime: incoming.fileMime ?? existing.fileMime,
      messageType: incoming.messageType,
      senderEmail: incoming.senderEmail.isNotEmpty
          ? incoming.senderEmail
          : existing.senderEmail,
      senderAvatarUrl: (incoming.senderAvatarUrl ?? '').trim().isNotEmpty
          ? incoming.senderAvatarUrl
          : existing.senderAvatarUrl,
      createdAt: incoming.createdAt.isNotEmpty
          ? incoming.createdAt
          : existing.createdAt,
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
      keyVersion: incoming.keyVersion > 0
          ? incoming.keyVersion
          : existing.keyVersion,
    );
  }

  /// Совпадение URL картинки для temp ↔ HTTP/WS (у presigned URL может отличаться только query).
  bool _sameOutgoingImageUrl(String? a, String? b) {
    final ta = (a ?? '').trim();
    final tb = (b ?? '').trim();
    if (ta.isEmpty || tb.isEmpty) return false;
    if (ta == tb) return true;
    try {
      final ua = Uri.parse(ta);
      final ub = Uri.parse(tb);
      return ua.host == ub.host && ua.path == ub.path;
    } catch (_) {
      return false;
    }
  }

  /// Один недавний исходящий temp с фото в статусе отправки — чтобы подхватить «пустой» WS-эвент от сервера.
  int? _singleRecentSendingImageTempIndex() {
    final self = widget.userId.toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    int? found;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (!m.id.startsWith('temp_')) continue;
      if (m.userId != self) continue;
      if (!m.hasImage) continue;
      final st = _tempMessageStates[m.id];
      if (st != null && st != _OutgoingUiState.sending) continue;
      final suffix = m.id.length > 5 ? m.id.substring(5) : '';
      final ts = int.tryParse(suffix) ?? 0;
      if (now - ts > 180000) continue;
      if (found != null) return null;
      found = i;
    }
    return found;
  }

  /// Прокрутить список к самому низу (к новым сообщениям).
  void _openGallery() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatGalleryScreen(chatId: widget.chatId, chatName: widget.chatName),
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  // ✅ Вычисляем высоту блока закрепленных сообщений
  double _getPinnedMessagesHeight() {
    if (_pinnedMessages.isEmpty) return 0.0;
    // Компактные размеры
    const headerHeight = 28.0; // Компактный заголовок
    const messageHeight = 32.0; // Компактная высота одного сообщения
    final messagesCount = _pinnedMessages.length > 3
        ? 3
        : _pinnedMessages.length;
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
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (!widget.isGroup)
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _accent1.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: Icon(Icons.call_rounded, color: _accent1),
                onPressed: _startVoiceCall,
                tooltip: 'Голосовой звонок',
              ),
            ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.search_rounded, color: _accent1),
              onPressed: _openSearch,
              tooltip: 'Поиск по сообщениям',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _accent1.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.people_rounded, color: _accent1),
              onPressed: _showMembersDialog,
              tooltip: 'Участники чата',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_accent1, _accent2]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _accent1.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: widget.isGroup
                ? IconButton(
                    icon: const Icon(
                      Icons.person_add_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _showAddMembersDialog,
                    tooltip: 'Добавить участников',
                  )
                : const SizedBox.shrink(),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert_rounded,
              color: scheme.onSurface.withValues(alpha: 0.75),
            ),
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
                    Icon(
                      Icons.photo_library_rounded,
                      color: Colors.purple.shade300,
                      size: 20,
                    ),
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
                    Icon(
                      Icons.download_rounded,
                      color: Colors.teal.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(_isExportingChat ? 'Экспорт...' : 'Экспорт чата'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'mentions',
                child: Row(
                  children: [
                    Icon(
                      Icons.alternate_email_rounded,
                      color: Colors.blue.shade300,
                      size: 20,
                    ),
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
                      Icon(
                        Icons.edit_rounded,
                        color: Colors.blueGrey.shade700,
                        size: 20,
                      ),
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
                      Icon(
                        Icons.link_rounded,
                        color: Colors.green.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Text('Пригласить (код)'),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_sweep_rounded,
                      color: Colors.red.shade400,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text('Очистить чат'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(
                      Icons.exit_to_app_rounded,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
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
                                  CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _accent1,
                                    ),
                                    strokeWidth: 3,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Загрузка сообщений...',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _listEntries.isEmpty
                          ? ChatEmptyMessages(accentColor: _accent1)
                          : RepaintBoundary(
                              child: Stack(
                                children: [
                                  // Отступ сверху для закрепленных сообщений
                                  Padding(
                                    padding: EdgeInsets.only(top: pinnedHeight),
                                    child: RefreshIndicator(
                                      onRefresh: () async {
                                        await _loadMessages();
                                      },
                                      color: _accent1,
                                      child: ListView.builder(
                                        key: ValueKey(
                                          'messages_list_${widget.chatId}',
                                        ),
                                        controller: _scrollController,
                                        reverse:
                                            false, // старые сверху, новые снизу
                                        physics:
                                            const AlwaysScrollableScrollPhysics(
                                              parent: ClampingScrollPhysics(),
                                            ),
                                        cacheExtent:
                                            800, // Предзагрузка элементов для плавного скролла
                                        addAutomaticKeepAlives:
                                            false, // Меньше памяти при длинных списках
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
                                            return ChatLoadingRow(
                                              accentColor: _accent1,
                                            );
                                          }
                                          if (entry is _DateHeaderEntry) {
                                            return ChatDateHeader(
                                              label: entry.label,
                                              accentColor: _accent1,
                                            );
                                          }
                                          final msg =
                                              _messages[(entry as _MessageEntry)
                                                  .index];
                                          final isMine =
                                              msg.userId == widget.userId;

                                          final isHighlighted =
                                              _highlightMessageId == msg.id;
                                          final messageBody = Slidable(
                                            key: _keyForMessage(msg.id),
                                            startActionPane: ActionPane(
                                              motion: const ScrollMotion(),
                                              extentRatio: 0.22,
                                              children: [
                                                SlidableAction(
                                                  onPressed: (_) =>
                                                      _setReplyAndScrollToInput(
                                                        msg,
                                                      ),
                                                  backgroundColor: _accent1
                                                      .withValues(
                                                        alpha: 0.85,
                                                      ),
                                                  foregroundColor:
                                                      Colors.white,
                                                  icon: Icons.reply_rounded,
                                                  label: 'Ответить',
                                                ),
                                              ],
                                            ),
                                            endActionPane: isMine
                                                ? ActionPane(
                                                    motion:
                                                        const ScrollMotion(),
                                                    extentRatio: 0.22,
                                                    children: [
                                                      SlidableAction(
                                                        onPressed: (_) =>
                                                            _showDeleteMessageDialog(
                                                              msg,
                                                            ),
                                                        backgroundColor:
                                                            Colors
                                                                .red
                                                                .shade400,
                                                        foregroundColor:
                                                            Colors.white,
                                                        icon: Icons
                                                            .delete_outline_rounded,
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
                                              chatId: widget.chatId
                                                  .toString(),
                                              myAvatarPlaceholder:
                                                  _myAvatarPlaceholderWidget,
                                              otherAvatarPlaceholder:
                                                  _otherAvatarWidget(
                                                    msg.senderEmail,
                                                  ),
                                              memberByHandle: _memberByHandle,
                                              onOpenSenderProfile: () =>
                                                  _openUserProfile(msg),
                                              onShowMessageMenu: () =>
                                                  _showMessageMenu(
                                                    msg,
                                                    isMine: isMine,
                                                  ),
                                              onOpenImage: () =>
                                                  _openImageViewer(msg),
                                              onOpenVideo: () =>
                                                  _openVideoViewer(msg),
                                              buildVoiceBubble: () =>
                                                  _buildVoiceBubble(
                                                    msg,
                                                    isMine: isMine,
                                                  ),
                                              isVoiceMessage: () =>
                                                  isVoiceMessage(msg),
                                              formatBytes: _formatBytes,
                                              formatDate: _formatDate,
                                              buildMessageStatus:
                                                  _buildMessageStatus(msg),
                                              onShowReactionPicker: () =>
                                                  _showReactionPicker(msg),
                                              onOpenUserProfileById:
                                                  (uid, label) =>
                                                      _openUserProfileById(
                                                        uid,
                                                        fallbackLabel: label,
                                                      ),
                                            ),
                                          );
                                          if (!_shouldFadeInMessage(msg.id)) {
                                            return messageBody;
                                          }
                                          return FadeScaleIn(
                                            key: ValueKey('fade_${msg.id}'),
                                            onComplete: () =>
                                                _messageIdsWithoutFade
                                                    .add(msg.id),
                                            child: messageBody,
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
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.97,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: _accent1.withValues(
                                              alpha: 0.18,
                                            ),
                                            width: 1.2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.06,
                                              ),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Компактный заголовок
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.push_pin,
                                                    size: 12,
                                                    color: _accent1.withValues(
                                                      alpha: 0.8,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Закреплено',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontSize: 11,
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 5,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: _accent1
                                                          .withValues(
                                                            alpha: 0.12,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      '${_pinnedMessages.length}',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
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
                                              padding: const EdgeInsets.only(
                                                left: 8,
                                                right: 8,
                                                bottom: 6,
                                              ),
                                              child: Column(
                                                children: _pinnedMessages.take(3).toList().asMap().entries.map((
                                                  entry,
                                                ) {
                                                  final index = entry.key;
                                                  final pinned = entry.value;
                                                  final isLast =
                                                      index ==
                                                      (_pinnedMessages.length >
                                                              3
                                                          ? 2
                                                          : _pinnedMessages
                                                                    .length -
                                                                1);

                                                  return Container(
                                                    margin: EdgeInsets.only(
                                                      bottom: isLast ? 0 : 4,
                                                    ),
                                                    child: Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        onTap: () {
                                                          final messageIndex =
                                                              _messages
                                                                  .indexWhere(
                                                                    (m) =>
                                                                        m.id ==
                                                                        pinned
                                                                            .id,
                                                                  );
                                                          if (messageIndex !=
                                                                  -1 &&
                                                              _scrollController
                                                                  .hasClients) {
                                                            final targetPosition =
                                                                (messageIndex *
                                                                    100.0) +
                                                                pinnedHeight;
                                                            _scrollController.animateTo(
                                                              targetPosition,
                                                              duration:
                                                                  const Duration(
                                                                    milliseconds:
                                                                        300,
                                                                  ),
                                                              curve: Curves
                                                                  .easeInOut,
                                                            );
                                                          }
                                                        },
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 6,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: AppColors
                                                                .primary
                                                                .withValues(
                                                                  alpha: 0.08,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                            border: Border.all(
                                                              color: scheme
                                                                  .outline
                                                                  .withValues(
                                                                    alpha: 0.18,
                                                                  ),
                                                              width: 1.2,
                                                            ),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons.push_pin,
                                                                size: 12,
                                                                color: _accent1
                                                                    .withValues(
                                                                      alpha:
                                                                          0.6,
                                                                    ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  pinned
                                                                          .content
                                                                          .isNotEmpty
                                                                      ? (pinned.content.length >
                                                                                40
                                                                            ? '${pinned.content.substring(0, 40)}...'
                                                                            : pinned.content)
                                                                      : 'Фото',
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w400,
                                                                    color: AppColors
                                                                        .onSurfaceVariantDark,
                                                                    height: 1.2,
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 6,
                                                              ),
                                                              Icon(
                                                                Icons
                                                                    .chevron_right,
                                                                size: 16,
                                                                color: AppColors
                                                                    .onSurfaceVariantDark
                                                                    .withValues(
                                                                      alpha:
                                                                          0.8,
                                                                    ),
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
                      border: Border(
                        top: BorderSide(
                          color: AppColors.borderDark.withValues(alpha: 0.5),
                        ),
                      ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // ✅ Индикатор очереди офлайн: сообщения будут отправлены при подключении
                            if (_messages.any((m) => m.id.startsWith('temp_')))
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.orange.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: Builder(
                                  builder: (context) {
                                    final tempMessages = _messages
                                        .where((m) => m.id.startsWith('temp_'))
                                        .toList();
                                    final queued = tempMessages
                                        .where(
                                          (m) =>
                                              _tempMessageStates[m.id] ==
                                              _OutgoingUiState.queued,
                                        )
                                        .length;
                                    final errors = tempMessages
                                        .where(
                                          (m) =>
                                              _tempMessageStates[m.id] ==
                                              _OutgoingUiState.error,
                                        )
                                        .length;
                                    final sending =
                                        tempMessages.length - queued - errors;
                                    final parts = <String>[];
                                    if (queued > 0)
                                      parts.add('в очереди: $queued');
                                    if (sending > 0)
                                      parts.add('отправляется: $sending');
                                    if (errors > 0)
                                      parts.add('ошибка: $errors');
                                    final details = parts.isEmpty
                                        ? 'сообщений: ${tempMessages.length}'
                                        : parts.join(', ');

                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.cloud_off_rounded,
                                              size: 18,
                                              color: Colors.orange.shade700,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Черновики отправки — $details',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.orange.shade900,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            TextButton.icon(
                                              onPressed: errors > 0
                                                  ? _retryErroredMessages
                                                  : null,
                                              icon: const Icon(
                                                Icons.refresh_rounded,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Повторить ошибки',
                                              ),
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            TextButton.icon(
                                              onPressed: tempMessages.isNotEmpty
                                                  ? _clearPendingQueue
                                                  : null,
                                              icon: const Icon(
                                                Icons.delete_sweep_rounded,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Очистить очередь',
                                              ),
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
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
                                  color: _accent1.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border(
                                    left: BorderSide(color: _accent1, width: 3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
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
                                                Icon(
                                                  Icons
                                                      .insert_drive_file_rounded,
                                                  size: 14,
                                                  color: Colors.grey.shade600,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    decodeFileNameForDisplay(
                                                      _replyToMessage!.fileName,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            )
                                          else if (_replyToMessage!.hasImage)
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.image,
                                                  size: 14,
                                                  color: Colors.grey.shade600,
                                                ),
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
                                              _replyToMessage!.content.length >
                                                      50
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
                            if (_selectedImagePath != null ||
                                _selectedImageBytes != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                height: 100,
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child:
                                          kIsWeb && _selectedImageBytes != null
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
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                        ),
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
                            if (_selectedFilePath != null ||
                                _selectedFileBytes != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: scheme.outline.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.insert_drive_file_rounded,
                                      color: _accent2,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _selectedFileName ?? 'Файл',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (_selectedFileSize != null)
                                            Text(
                                              _formatBytes(_selectedFileSize!),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.65),
                                              ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: scheme.outline.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _e2eeStatusText()!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.8,
                                    ),
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
                              onPickVideo: _pickVideo,
                              onPickVideoFromCamera: _pickVideoFromCamera,
                              onToggleVoiceRecording: _toggleVoiceRecording,
                              onVoiceLongPressStart:
                                  _startVoiceRecordingIfNotRecording,
                              onVoiceLongPressEnd:
                                  _stopAndSendVoiceRecordingIfRecording,
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
