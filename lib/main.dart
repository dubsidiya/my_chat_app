import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:intl/date_symbol_data_local.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'screens/eula_consent_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_tabs_screen.dart';
import 'services/storage_service.dart';
import 'services/local_messages_service.dart';
import 'services/push_notification_service.dart';
import 'services/websocket_service.dart';
import 'services/auth_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Оборачивает приложение в ScaffoldMessenger, который перед показом нового SnackBar
/// всегда скрывает текущий — так два вызова подряд не конфликтуют и не «зависают».
class _AutoHideScaffoldMessenger extends ScaffoldMessenger {
  const _AutoHideScaffoldMessenger({required super.child});

  @override
  ScaffoldMessengerState createState() => _AutoHideScaffoldMessengerState();
}

class _AutoHideScaffoldMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    hideCurrentSnackBar();
    return super.showSnackBar(snackBar, snackBarAnimationStyle: snackBarAnimationStyle);
  }
}

void main() {
  // Обработка ошибок Flutter
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      print('Flutter Error: ${details.exception}');
      print('Stack trace: ${details.stack}');
    }
  };

  // Обработка асинхронных ошибок
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en_US');
    await LocalMessagesService.init();
    await PushNotificationService.init(navigatorKey);
    runApp(const MyApp());
  }, (error, stack) {
    if (kDebugMode) {
      print('Uncaught error: $error');
      print('Stack trace: $stack');
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ThemeData? _appTheme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WebSocketService.instance.connectIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    _appTheme ??= buildAppTheme();

    return _AutoHideScaffoldMessenger(
      child: MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Chat App',
      theme: _appTheme!,
      home: FutureBuilder<Map<String, dynamic>?>(
        future: () async {
          final userData = await StorageService.getUserData();
          if (userData == null || userData['token'] == null) return null;
          final sessionState = await AuthService().hasValidSession();
          if (sessionState == false) {
            await StorageService.clearUserData();
            return null;
          }
          final eulaAccepted = await StorageService.getEulaAccepted(userData['id']!);
          return {'userData': userData, 'eulaAccepted': eulaAccepted};
        }(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.backgroundDark,
                      AppColors.surfaceDark,
                      AppColors.primaryDeep,
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGlow),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Загрузка...',
                        style: TextStyle(
                          color: AppColors.onSurfaceDark.withValues(alpha: 0.85),
                          fontSize: 16,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final data = snapshot.data;
          if (data != null) {
            final userData = data['userData'] as Map<String, dynamic>;
            final eulaAccepted = data['eulaAccepted'] as bool;
            final userIdentifier = (userData['email'] ?? userData['username'] ?? '') as String;
            final isSuperuser = userData['isSuperuser'] == 'true';
            final displayName = userData['displayName']?.toString();
            final avatarUrl = userData['avatarUrl']?.toString();
            final userId = userData['id'] as String;
            if (eulaAccepted) {
              return MainTabsScreen(
                userId: userId,
                userEmail: userIdentifier,
                displayName: displayName,
                avatarUrl: avatarUrl,
                isSuperuser: isSuperuser,
              );
            }
            return EulaConsentScreen(
              userId: userId,
              userEmail: userIdentifier,
              displayName: displayName,
              avatarUrl: avatarUrl,
              isSuperuser: isSuperuser,
            );
          }

          return const LoginScreen();
        },
      ),
    ),
    );
  }
}
