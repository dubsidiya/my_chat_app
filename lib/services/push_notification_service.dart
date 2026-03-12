import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../screens/chat_screen.dart';
import 'storage_service.dart';

/// Канал для уведомлений о сообщениях (Android).
const String _channelId = 'chat_messages';
const String _channelName = 'Сообщения в чатах';

/// Сервис push-уведомлений через Firebase Cloud Messaging.
/// Если Firebase не настроен (нет GoogleService-Info.plist и т.д.), инициализация пропускается без ошибки.
/// В foreground при получении FCM показывается локальное уведомление (flutter_local_notifications).
class PushNotificationService {
  static bool _initialized = false;
  static String? _fcmToken;
  static GlobalKey<NavigatorState>? _navigatorKey;

  /// Текущий открытый чат (id). Если пришёл push по этому чату — уведомление не показываем.
  static String? _currentChatId;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool get isInitialized => _initialized;

  /// Вызвать при входе в чат. Передай [chatId] или null при выходе из чата.
  static void setCurrentChatId(String? chatId) {
    _currentChatId = chatId;
  }

  /// Вызвать после [WidgetsFlutterBinding.ensureInitialized], до [runApp].
  /// [navigatorKey] — ключ навигатора приложения для перехода в чат при нажатии на уведомление.
  static Future<void> init(GlobalKey<NavigatorState>? navigatorKey) async {
    _navigatorKey = navigatorKey;
    // На веб Firebase без конфигурации падает с assertion — не вызываем initializeApp.
    if (kIsWeb) {
      if (kDebugMode) print('PushNotificationService: web platform, skip Firebase');
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
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    final messaging = FirebaseMessaging.instance;

    // iOS: показывать баннер/звук при получении пуша в foreground
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (kDebugMode) print('PushNotificationService: permission denied');
      return;
    }

    _initialized = true;

    // Токен для отправки на бэкенд
    messaging.getToken().then((token) {
      if (token != null) {
        _fcmToken = token;
        if (kDebugMode) print('PushNotificationService: FCM token received');
        sendTokenToBackendIfNeeded();
      }
    }).catchError((e) {
      if (kDebugMode) print('PushNotificationService: getToken error: $e');
    });

    // Обновление токена
    messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
      sendTokenToBackendIfNeeded();
    });

    // Уведомление открыто из фона/закрытого состояния
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) _handleOpenFromNotification(message.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleOpenFromNotification(message.data);
    });

    // Сообщение при открытом приложении — показываем локальное уведомление (если не в этом чате)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      if (_currentChatId != null && data['chatId']?.toString() == _currentChatId) {
        return; // уже в этом чате — не показываем
      }
      final notification = message.notification;
      final title = notification?.title ?? 'Новое сообщение';
      final body = notification?.body ?? 'Сообщение в чате';
      _showForegroundNotification(title: title, body: body, data: data);
    });
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
      if (kDebugMode) print('PushNotificationService: invalid payload $payload');
    }
  }

  static Future<void> _showForegroundNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final payload = jsonEncode(data);
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Уведомления о новых сообщениях в чатах',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    final id = DateTime.now().millisecondsSinceEpoch.remainder(0x7FFFFFFF);
    await _localNotifications.show(id, title, body, details, payload: payload);
  }

  static void _handleOpenFromNotification(Map<String, dynamic> data) {
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
      if (userData == null || userData['id'] == null || userData['token'] == null) return;
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

  /// Отправить FCM-токен на бэкенд (если пользователь залогинен).
  static Future<void> sendTokenToBackendIfNeeded() async {
    final token = _fcmToken;
    if (token == null || token.isEmpty) return;

    final userData = await StorageService.getUserData();
    final authToken = userData?['token'];
    if (authToken == null || authToken.isEmpty) return;

    final url = Uri.parse('${ApiConfig.baseUrl}/auth/fcm-token');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'fcmToken': token}),
      );
      if (kDebugMode) {
        print('PushNotificationService: fcm-token response ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('PushNotificationService: sendToken error: $e');
    }
  }

  /// Очистить FCM-токен на бэкенде (вызывать перед выходом из аккаунта).
  static Future<void> clearTokenOnBackend() async {
    final userData = await StorageService.getUserData();
    final authToken = userData?['token'];
    if (authToken == null || authToken.isEmpty) return;

    final url = Uri.parse('${ApiConfig.baseUrl}/auth/fcm-token');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'fcmToken': ''}),
      );
      if (kDebugMode) {
        print('PushNotificationService: clear fcm-token response ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('PushNotificationService: clearToken error: $e');
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
