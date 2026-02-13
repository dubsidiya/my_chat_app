import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../screens/chat_screen.dart';
import 'storage_service.dart';

/// Сервис push-уведомлений через Firebase Cloud Messaging.
/// Если Firebase не настроен (нет GoogleService-Info.plist и т.д.), инициализация пропускается без ошибки.
class PushNotificationService {
  static bool _initialized = false;
  static String? _fcmToken;
  static GlobalKey<NavigatorState>? _navigatorKey;

  static bool get isInitialized => _initialized;

  /// Вызвать после [WidgetsFlutterBinding.ensureInitialized], до [runApp].
  /// [navigatorKey] — ключ навигатора приложения для перехода в чат при нажатии на уведомление.
  static Future<void> init(GlobalKey<NavigatorState>? navigatorKey) async {
    _navigatorKey = navigatorKey;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) {
        print('PushNotificationService: Firebase not configured, skip: $e');
      }
      return;
    }

    final messaging = FirebaseMessaging.instance;

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

    // Сообщение при открытом приложении (опционально можно показать in-app)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print('PushNotificationService: onMessage ${message.notification?.title}');
      }
    });
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

      navigator.push(
        MaterialPageRoute(
          builder: (_) => _ChatScreenRoute(
            userId: userId,
            userEmail: userEmail,
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
}

/// Внутренний виджет для перехода в чат по нажатию на push.
class _ChatScreenRoute extends StatelessWidget {
  final String userId;
  final String userEmail;
  final String chatId;
  final String chatName;
  final bool isGroup;

  const _ChatScreenRoute({
    required this.userId,
    required this.userEmail,
    required this.chatId,
    required this.chatName,
    required this.isGroup,
  });

  @override
  Widget build(BuildContext context) {
    return ChatScreen(
      userId: userId,
      userEmail: userEmail,
      chatId: chatId,
      chatName: chatName,
      isGroup: isGroup,
    );
  }
}
