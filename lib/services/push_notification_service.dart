import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/chat_screen.dart';
import '../utils/android_full_screen_intent.dart';
import '../utils/push_payload.dart';
import 'storage_service.dart';
import 'push_device_service.dart';
import 'voice_call_service.dart';
import 'group_voice_call_service.dart';
import 'ios_callkit_service.dart';
import 'websocket_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!isCallReconciliationPushData(message.data)) return;
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase can already be initialized in the background isolate.
  }
  await PushNotificationService.cancelCallNotificationData(message.data);
}

/// Канал для уведомлений о сообщениях (Android).
const String _channelId = 'chat_messages';
const String _channelName = 'Сообщения в чатах';

/// Канал для входящих голосовых звонков (Android).
const String _callChannelId = 'voice_calls';
const String _callChannelName = 'Голосовые звонки';

/// Сервис push-уведомлений через Firebase Cloud Messaging.
/// Если Firebase не настроен (нет GoogleService-Info.plist и т.д.), инициализация пропускается без ошибки.
/// В foreground при получении FCM показывается локальное уведомление (flutter_local_notifications).
class PushNotificationService {
  static bool _initialized = false;
  static bool _backgroundHandlerRegistered = false;
  static String? _fcmToken;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static StreamSubscription<dynamic>? _callEventSubscription;
  static final Map<String, CallNotificationIdentity>
  _callNotificationIdentities = {};

  /// Текущий открытый чат (id). Если пришёл push по этому чату — уведомление не показываем.
  static String? _currentChatId;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool get isInitialized => _initialized;
  static String? get currentFcmToken => _fcmToken;

  /// Register before [runApp] so Android can reconcile a call notification
  /// while the UI isolate is suspended.
  static void registerBackgroundHandler() {
    if (kIsWeb || _backgroundHandlerRegistered) return;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _backgroundHandlerRegistered = true;
  }

  /// Вызвать при входе в чат. Передай [chatId] или null при выходе из чата.
  static void setCurrentChatId(String? chatId) {
    _currentChatId = chatId;
  }

  /// Вызвать после [WidgetsFlutterBinding.ensureInitialized], до [runApp].
  /// [navigatorKey] — ключ навигатора приложения для перехода в чат при нажатии на уведомление.
  static Future<void> init(GlobalKey<NavigatorState>? navigatorKey) async {
    _navigatorKey = navigatorKey;
    registerBackgroundHandler();
    // На веб Firebase без конфигурации падает с assertion — не вызываем initializeApp.
    if (kIsWeb) {
      if (kDebugMode) {
        print('PushNotificationService: web platform, skip Firebase');
      }
      return;
    }
    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) {
        print('PushNotificationService: Firebase not configured, skip: $e');
      }
      return;
    }

    // Локальные уведомления (для foreground и обработка тапа по локальному)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    // Android: канал для сообщений
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Уведомления о новых сообщениях в чатах',
      importance: Importance.high,
      playSound: true,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    const androidCallChannel = AndroidNotificationChannel(
      _callChannelId,
      _callChannelName,
      description: 'Входящие голосовые звонки',
      importance: Importance.max,
      playSound: true,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidCallChannel);

    final messaging = FirebaseMessaging.instance;

    // iOS: показывать баннер/звук при получении пуша в foreground
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _initialized = true;
    _attachMessagingHandlers(messaging);

    // На iOS системный диалог push блокирует старт, если await-ить в main().
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return;
    }

    await _requestPermissionAndRegisterToken(messaging);
  }

  /// Запросить разрешение на уведомления после появления UI (не блокировать splash).
  static Future<void> requestPermissionIfNeeded() async {
    if (kIsWeb || !_initialized) return;
    try {
      await _requestPermissionAndRegisterToken(FirebaseMessaging.instance);
    } catch (e) {
      if (kDebugMode) {
        print('PushNotificationService.requestPermissionIfNeeded: $e');
      }
    }
  }

  static Future<void> _requestPermissionAndRegisterToken(
    FirebaseMessaging messaging,
  ) async {
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (kDebugMode) print('PushNotificationService: permission denied');
      return;
    }

    // Android 14+: full-screen incoming-call intent may be restricted. We never
    // auto-jump to Settings here; notifications fall back to heads-up when
    // denied. Call AndroidFullScreenIntent.ensureReady(openSettingsIfNeeded: true)
    // from an in-app prompt if product wants a guided enable flow.
    if (kDebugMode && AndroidFullScreenIntent.isSupported) {
      final ok = await AndroidFullScreenIntent.canUseFullScreenIntent();
      if (!ok) {
        debugPrint(
          'PushNotificationService: full-screen intent disabled — '
          'incoming calls use heads-up fallback',
        );
      }
    }

    // Токен для отправки на бэкенд
    messaging
        .getToken()
        .then((token) {
          if (token != null) {
            _fcmToken = token;
            if (kDebugMode) {
              print('PushNotificationService: FCM token received');
            }
            sendTokenToBackendIfNeeded();
          }
        })
        .catchError((e) {
          if (kDebugMode) print('PushNotificationService: getToken error: $e');
        });
  }

  static void _attachMessagingHandlers(FirebaseMessaging messaging) {
    messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
      sendTokenToBackendIfNeeded();
    });

    _callEventSubscription ??= WebSocketService.instance.stream.listen((event) {
      if (event is! Map) return;
      final type = event['type']?.toString();
      if (type == 'call_answered_elsewhere' ||
          type == 'call_reject' ||
          type == 'call_hangup' ||
          type == 'gcall_ended' ||
          type == 'lkcall_ended') {
        unawaited(cancelCallNotificationData(Map<String, dynamic>.from(event)));
      }
    });

    FirebaseMessaging.instance.getInitialMessage().then((
      RemoteMessage? message,
    ) {
      if (message != null) _handleOpenFromNotification(message.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleOpenFromNotification(message.data);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      if (isCallReconciliationPushData(data)) {
        unawaited(cancelCallNotificationData(data));
        return;
      }
      if (_isIncomingCallData(data)) {
        if (shouldDiscardIncomingCallPush(data)) {
          unawaited(cancelCallNotificationData(data));
          return;
        }
        _handleIncomingCallPush(data, message.notification);
        return;
      }
      if (_currentChatId != null &&
          data['chatId']?.toString() == _currentChatId) {
        return;
      }
      final notification = message.notification;
      final title = notification?.title ?? 'Новое сообщение';
      final body = notification?.body ?? 'Сообщение в чате';
      if (_shouldSkipLocalForegroundMessageNotification(message)) {
        return;
      }
      _showForegroundNotification(title: title, body: body, data: data);
    });
  }

  static bool _isIncomingCallData(Map<String, dynamic> data) {
    return isIncomingCallPushData(data);
  }

  /// На Apple-платформах FCM с notification payload уже показывается системой в foreground.
  static bool _shouldSkipLocalForegroundMessageNotification(
    RemoteMessage message,
  ) {
    return !shouldShowForegroundLocalNotification(
      platform: defaultTargetPlatform,
      hasRemoteNotification: message.notification != null,
    );
  }

  static void _handleIncomingCallPush(
    Map<String, dynamic> data,
    RemoteNotification? notification, {
    bool allowLocalNotification = true,
  }) {
    if (shouldDiscardIncomingCallPush(data)) {
      unawaited(cancelCallNotificationData(data));
      return;
    }
    if (data['type']?.toString() == 'incoming_livekit_group_call' &&
        !isLiveKitGroupCallPushData(data)) {
      return;
    }
    final callId = data['callId']?.toString() ?? '';
    final chatId = data['chatId']?.toString() ?? '';
    final peerUserId = data['fromUserId']?.toString() ?? '';
    final peerLabel =
        data['fromLabel']?.toString() ??
        data['fromEmail']?.toString() ??
        data['chatName']?.toString() ??
        'Звонок';
    final chatName = data['chatName']?.toString() ?? peerLabel;
    final isGroup =
        data['type']?.toString() == 'incoming_group_call' ||
        data['type']?.toString() == 'incoming_livekit_group_call' ||
        data['isGroup']?.toString() == '1';
    if (callId.isEmpty || chatId.isEmpty) return;
    final dedupeKey = incomingCallPushDedupeKey(data);
    _callNotificationIdentities[dedupeKey] = callNotificationIdentity(data);
    final expiresAt = parseCallPushExpiry(data);
    final shouldShowLocal =
        allowLocalNotification &&
        shouldShowForegroundLocalNotification(
          platform: defaultTargetPlatform,
          hasRemoteNotification: notification != null,
        );

    unawaited(WebSocketService.instance.connectIfNeeded());

    if (isGroup) {
      final liveKit = isLiveKitGroupCallPushData(data);
      final mediaType =
          (data['initialMediaType'] ?? data['mediaType'])?.toString() == 'video'
          ? GroupCallMediaType.video
          : GroupCallMediaType.audio;
      final before = GroupVoiceCallService.instance.snapshot;
      GroupVoiceCallService.instance.applyIncomingFromPush(
        callId: callId,
        chatId: chatId,
        chatName: chatName,
        fromUserId: peerUserId,
        fromLabel: peerLabel,
        expiresAt: expiresAt,
        transport: liveKit
            ? GroupCallTransport.livekit
            : GroupCallTransport.mesh,
        mediaType: mediaType,
      );
      final after = GroupVoiceCallService.instance.snapshot;
      if (before.isActive &&
          before.callId == callId &&
          before.transport ==
              (liveKit
                  ? GroupCallTransport.livekit
                  : GroupCallTransport.mesh)) {
        return;
      }
      if (after.callId != callId || after.phase != GroupCallPhase.incoming) {
        return;
      }
      if (!shouldShowLocal) return;
      final title =
          notification?.title ??
          (mediaType == GroupCallMediaType.video
              ? 'Групповой видеозвонок'
              : 'Групповой звонок');
      final body =
          notification?.body ??
          (mediaType == GroupCallMediaType.video
              ? '$peerLabel начинает видеозвонок'
              : '$peerLabel начинает звонок');
      unawaited(
        _showForegroundNotification(
          title: title,
          body: body,
          data: data,
          isCall: true,
        ),
      );
      return;
    }

    if (peerUserId.isEmpty) return;
    final mediaType = callMediaTypeFromRaw(
      data['mediaType'] ?? data['media_type'],
    );
    final before = VoiceCallService.instance.snapshot;
    VoiceCallService.instance.applyIncomingFromPush(
      callId: callId,
      chatId: chatId,
      peerUserId: peerUserId,
      peerLabel: peerLabel,
      mediaType: mediaType,
      expiresAt: expiresAt,
    );
    final after = VoiceCallService.instance.snapshot;

    // Уже звоним по WebSocket — не дублируем баннер.
    if (before.isActive && before.callId == callId) return;
    if (after.callId != callId || after.phase != VoiceCallPhase.incoming) {
      return;
    }
    if (!shouldShowLocal) return;

    final title =
        notification?.title ??
        (mediaType == CallMediaType.video
            ? 'Входящий видеозвонок'
            : 'Входящий звонок');
    final body =
        notification?.body ??
        (mediaType == CallMediaType.video
            ? '$peerLabel звонит с видео'
            : '$peerLabel звонит');
    unawaited(
      _showForegroundNotification(
        title: title,
        body: body,
        data: data,
        isCall: true,
      ),
    );
  }

  static void _onLocalNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _handleOpenFromNotification(
        data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
      );
    } catch (_) {
      if (kDebugMode) {
        print('PushNotificationService: invalid payload $payload');
      }
    }
  }

  static Future<void> _showForegroundNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
    bool isCall = false,
  }) async {
    final payload = jsonEncode(data);
    final callIdentity = isCall ? callNotificationIdentity(data) : null;
    final allowFullScreen =
        isCall && await AndroidFullScreenIntent.canUseFullScreenIntent();
    final androidDetails = AndroidNotificationDetails(
      isCall ? _callChannelId : _channelId,
      isCall ? _callChannelName : _channelName,
      channelDescription: isCall
          ? 'Входящие голосовые звонки'
          : 'Уведомления о новых сообщениях в чатах',
      importance: isCall ? Importance.max : Importance.high,
      priority: isCall ? Priority.max : Priority.high,
      playSound: true,
      category: isCall ? AndroidNotificationCategory.call : null,
      fullScreenIntent: allowFullScreen,
      tag: callIdentity?.tag,
      timeoutAfter: isCall ? callNotificationTimeoutMs(data) : null,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    final id =
        callIdentity?.id ??
        DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF);
    await _localNotifications.show(id, title, body, details, payload: payload);
  }

  static Future<void> cancelCallNotificationData(
    Map<String, dynamic> data,
  ) async {
    await IOSCallKitService.instance.handleReconciliationPush(data);
    final callId =
        data['callId']?.toString() ?? data['call_id']?.toString() ?? '';
    final dedupeKey = incomingCallPushDedupeKey(data);
    final identity =
        _callNotificationIdentities[dedupeKey] ??
        callNotificationIdentity(data);
    try {
      await _localNotifications.cancel(identity.id, tag: identity.tag);
    } catch (_) {
      if (kDebugMode) {
        print('PushNotificationService: call notification cancel failed');
      }
    } finally {
      if (callId.isNotEmpty) _callNotificationIdentities.remove(dedupeKey);
    }
  }

  static void _handleOpenFromNotification(Map<String, dynamic> data) {
    if (isCallReconciliationPushData(data)) {
      unawaited(cancelCallNotificationData(data));
      return;
    }
    if (_isIncomingCallData(data)) {
      if (shouldDiscardIncomingCallPush(data)) {
        unawaited(cancelCallNotificationData(data));
        return;
      }
      _handleIncomingCallPush(data, null, allowLocalNotification: false);
      return;
    }
    final chatId = data['chatId']?.toString();
    if (chatId == null || chatId.isEmpty) return;
    final chatName = data['chatName']?.toString() ?? 'Чат';
    final isGroup = data['isGroup'] == '1';

    _navigateToChat(chatId: chatId, chatName: chatName, isGroup: isGroup);
  }

  static void _navigateToChat({
    required String chatId,
    required String chatName,
    required bool isGroup,
  }) {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;

    StorageService.getUserData().then((userData) {
      if (userData == null ||
          userData['id'] == null ||
          userData['token'] == null) {
        return;
      }
      final userId = userData['id']!;
      final userEmail = userData['email'] ?? userData['username'] ?? '';
      final displayName = userData['displayName']?.toString();

      navigator.push(
        MaterialPageRoute(
          builder: (_) => _ChatScreenRoute(
            userId: userId,
            userEmail: userEmail,
            displayName: displayName,
            chatId: chatId,
            chatName: chatName,
            isGroup: isGroup,
          ),
        ),
      );
    });
  }

  /// Sync this installation's normal FCM token after login/start/refresh.
  static Future<void> sendTokenToBackendIfNeeded() async {
    final token = _fcmToken;
    try {
      final result = token == null || token.isEmpty
          ? null
          : await PushDeviceSyncService.instance.syncNormalToken(token);
      await IOSCallKitService.instance.syncVoipRegistration();
      if (kDebugMode) {
        print(
          'PushNotificationService: device sync '
          '${result?.statusCode ?? 'skipped'}',
        );
      }
    } catch (_) {
      if (kDebugMode) {
        print('PushNotificationService: device sync failed');
      }
    }
  }

  /// Deregister only this installation; a delayed logout cannot affect a row
  /// that has already moved to another account.
  static Future<void> clearTokenOnBackend() async {
    try {
      final cleared = await PushDeviceSyncService.instance.deregister();
      if (kDebugMode) {
        print(
          'PushNotificationService: device deregistration '
          '${cleared ? 'accepted' : 'skipped'}',
        );
      }
    } catch (_) {
      if (kDebugMode) {
        print('PushNotificationService: device deregistration failed');
      }
    }
  }
}

/// Внутренний виджет для перехода в чат по нажатию на push.
class _ChatScreenRoute extends StatelessWidget {
  final String userId;
  final String userEmail;
  final String? displayName;
  final String chatId;
  final String chatName;
  final bool isGroup;

  const _ChatScreenRoute({
    required this.userId,
    required this.userEmail,
    this.displayName,
    required this.chatId,
    required this.chatName,
    required this.isGroup,
  });

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      userId: userId,
      userEmail: userEmail,
      displayName: displayName,
      chatId: chatId,
      chatName: chatName,
      isGroup: isGroup,
    );
  }
}
