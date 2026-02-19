import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:intl/date_symbol_data_local.dart';
import 'theme/app_colors.dart';
import 'screens/eula_consent_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_tabs_screen.dart';
import 'services/storage_service.dart';
import 'services/local_messages_service.dart';
import 'services/push_notification_service.dart';
import 'services/websocket_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

  ThemeData _buildTheme() {
    const scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.onSurfaceDark,
      primaryContainer: AppColors.cardElevatedDark,
      onPrimaryContainer: AppColors.accent,
      secondary: AppColors.primaryGlow,
      onSecondary: AppColors.backgroundDark,
      surface: AppColors.surfaceDark,
      onSurface: AppColors.onSurfaceDark,
      onSurfaceVariant: AppColors.onSurfaceVariantDark,
      outline: AppColors.borderDark,
      surfaceContainerHighest: AppColors.cardDark,
    );

    const surface = AppColors.surfaceDark;
    const card = AppColors.cardDark;
    const outline = AppColors.borderDark;

    return ThemeData(
        brightness: Brightness.dark,
        colorScheme: scheme,
        primaryColor: scheme.primary,
        scaffoldBackgroundColor: surface,
        cardColor: card,
        dividerColor: outline,
        visualDensity: VisualDensity.standard,
        useMaterial3: true,
        listTileTheme: ListTileThemeData(
          iconColor: scheme.onSurface.withValues(alpha: 0.85),
          textColor: scheme.onSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          selectedColor: AppColors.primary.withValues(alpha: 0.28),
          disabledColor: scheme.onSurface.withValues(alpha: 0.08),
          labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
          secondaryLabelStyle: TextStyle(color: scheme.onSurface),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: outline),
          ),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: AppColors.accent,
          unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.6),
          indicatorColor: AppColors.primaryGlow,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: card,
          foregroundColor: scheme.onSurface,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            letterSpacing: 0.5,
          ),
          iconTheme: IconThemeData(color: scheme.onSurface),
        ),
        cardTheme: CardThemeData(
          elevation: 8,
          color: card,
          shadowColor: AppColors.primaryGlow.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: outline.withValues(alpha: 0.6)),
          ),
          margin: EdgeInsets.zero,
        ),
        dialogTheme: DialogThemeData(
          elevation: 16,
          backgroundColor: card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.primaryGlow.withValues(alpha: 0.4)),
          ),
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
          contentTextStyle: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: scheme.onSurface.withValues(alpha: 0.9),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: card,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: card,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            side: BorderSide(color: outline),
          ),
          showDragHandle: true,
          dragHandleColor: AppColors.primaryGlow.withValues(alpha: 0.6),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: outline),
          ),
          textStyle: TextStyle(color: scheme.onSurface),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          elevation: 12,
          backgroundColor: AppColors.cardElevatedDark,
          contentTextStyle: TextStyle(color: AppColors.onSurfaceDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.primaryGlow.withValues(alpha: 0.5)),
          ),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: AppColors.primaryGlow,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.primary.withValues(alpha: 0.08),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primaryGlow, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 8,
            shadowColor: AppColors.primaryGlow.withValues(alpha: 0.6),
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onSurfaceDark,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(color: outline),
            foregroundColor: scheme.onSurface,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            foregroundColor: AppColors.primaryGlow,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    _appTheme ??= _buildTheme();

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Chat App',
      theme: _appTheme!,
      home: FutureBuilder<Map<String, dynamic>?>(
        future: () async {
          final userData = await StorageService.getUserData();
          if (userData == null || userData['token'] == null) return null;
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
                          color: AppColors.onSurfaceDark.withValues(alpha: 0.9),
                          fontSize: 16,
                          letterSpacing: 0.5,
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
    );
  }
}
