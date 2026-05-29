import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:intl/date_symbol_data_local.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
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
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // runApp сразу — иначе на iOS виден белый LaunchScreen/Main.storyboard,
    // пока в main() await-ятся Hive, Firebase и т.д.
    runApp(const _BootstrapApp());
  }, (error, stack) {
    if (kDebugMode) {
      print('Uncaught error: $error');
      print('Stack trace: $stack');
    }
  });
}

/// Стартовая оболочка: показывает экран загрузки, пока идёт init в фоне.
class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await initializeDateFormatting('ru').timeout(const Duration(seconds: 8));
      await initializeDateFormatting('en_US').timeout(const Duration(seconds: 8));
    } catch (e) {
      if (kDebugMode) print('date formatting init: $e');
    }
    try {
      await LocalMessagesService.init().timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) print('LocalMessagesService.init: $e');
    }
    try {
      await ThemeController.instance.loadFromStorage().timeout(const Duration(seconds: 5));
    } catch (e) {
      if (kDebugMode) print('ThemeController.loadFromStorage: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: _StartupLoadingScreen(),
          );
        }
        if (snapshot.hasError) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Ошибка запуска: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }
        return const MyApp();
      },
    );
  }
}

/// Экран до [MyApp]: тот же градиент, что и при проверке сессии.
class _StartupLoadingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isLight = AppColors.isLight;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLight
                ? [
                    AppColors.backgroundDark,
                    AppColors.cardDark,
                    AppColors.accent.withValues(alpha: 0.45),
                  ]
                : [
                    AppColors.backgroundDark,
                    AppColors.surfaceDark,
                    AppColors.primaryDeep,
                  ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.cyberGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGlow.withValues(alpha: 0.55),
                      blurRadius: 36,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: AppColors.cyberAccent.withValues(alpha: 0.35),
                      blurRadius: 48,
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.forum_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 32),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyberAccent),
                strokeWidth: 3,
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
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MyAppState createState() => _MyAppState();
}

/// Проверка сессии при старте; не блокируем UI дольше [kStartupSessionTimeout].
const Duration kStartupSessionTimeout = Duration(seconds: 12);

Future<Map<String, dynamic>?> _resolveStartupSession() async {
  final userData = await StorageService.getUserData();
  if (userData == null || userData['token'] == null) return null;

  bool? sessionState;
  try {
    sessionState = await AuthService().hasValidSession().timeout(
      kStartupSessionTimeout,
      onTimeout: () => null,
    );
  } catch (e) {
    if (kDebugMode) print('startup session check: $e');
    sessionState = null;
  }

  if (sessionState == false) {
    await StorageService.clearUserData();
    return null;
  }

  final eulaAccepted = await StorageService.getEulaAccepted(userData['id']!);
  return {'userData': userData, 'eulaAccepted': eulaAccepted};
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final Future<Map<String, dynamic>?> _sessionFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionFuture = _resolveStartupSession();
    unawaited(PushNotificationService.init(navigatorKey));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PushNotificationService.requestPermissionIfNeeded());
    });
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
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final theme = buildAppTheme(ThemeController.instance.variant);
        return _AutoHideScaffoldMessenger(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Chat App',
            theme: theme,
            home: FutureBuilder<Map<String, dynamic>?>(
              future: _sessionFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _StartupLoadingScreen();
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
      },
    );
  }
}
