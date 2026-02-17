import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/login_screen.dart';
import 'screens/main_tabs_screen.dart';
import 'services/storage_service.dart';
import 'services/local_messages_service.dart';
import 'services/push_notification_service.dart';

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

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final isDark = await StorageService.getThemeMode();
    if (mounted) {
      setState(() {
        _isDarkMode = isDark;
      });
    }
  }

  void toggleTheme(bool isDark) {
    if (mounted) {
      setState(() {
        _isDarkMode = isDark;
      });
    }
    StorageService.saveThemeMode(isDark);
  }

  ThemeData _buildTheme(Brightness brightness) {
    const seed = Color(0xFF667eea);
      final isDark = brightness == Brightness.dark;
      final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

      final surface = isDark ? const Color(0xFF0F1115) : const Color(0xFFF6F7FB);
      final card = isDark ? const Color(0xFF161A22) : Colors.white;
      final outline = isDark ? Colors.white.withValues(alpha:0.10) : Colors.black.withValues(alpha:0.08);

      return ThemeData(
        brightness: brightness,
        colorScheme: scheme,
        primaryColor: scheme.primary,
        scaffoldBackgroundColor: surface,
        cardColor: card,
        dividerColor: outline,
        visualDensity: VisualDensity.standard,
        useMaterial3: true,
        listTileTheme: ListTileThemeData(
          iconColor: scheme.onSurface.withValues(alpha:0.80),
          textColor: scheme.onSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          dense: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04),
          selectedColor: scheme.primary.withValues(alpha:0.18),
          disabledColor: scheme.onSurface.withValues(alpha:0.08),
          labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
          secondaryLabelStyle: TextStyle(color: scheme.onSurface),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: outline),
          ),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: scheme.primary,
          unselectedLabelColor: scheme.onSurface.withValues(alpha:0.55),
          indicatorColor: scheme.primary,
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
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
          iconTheme: IconThemeData(color: scheme.onSurface),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: card,
          shadowColor: Colors.black.withValues(alpha:isDark ? 0.30 : 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: outline),
          ),
          margin: EdgeInsets.zero,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: outline),
          ),
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
          contentTextStyle: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: scheme.onSurface.withValues(alpha:0.85),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: card,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: card,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            side: BorderSide(color: outline),
          ),
          showDragHandle: true,
          dragHandleColor: scheme.onSurface.withValues(alpha:0.25),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: outline),
          ),
          textStyle: TextStyle(color: scheme.onSurface),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.inverseSurface,
          contentTextStyle: TextStyle(color: scheme.onInverseSurface),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: scheme.primary,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? Colors.white.withValues(alpha:0.06) : Colors.black.withValues(alpha:0.04),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    _lightTheme ??= _buildTheme(Brightness.light);
    _darkTheme ??= _buildTheme(Brightness.dark);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Chat App',
      theme: _lightTheme!,
      darkTheme: _darkTheme!,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: FutureBuilder<Map<String, String>?>(
        future: StorageService.getUserData(),
        builder: (context, snapshot) {
          // Показываем загрузку пока проверяем сохраненные данные
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              body: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.shade700,
                      Colors.blue.shade500,
                    ],
                  ),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Загрузка...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // Если есть сохраненные данные и токен - автоматически входим
          if (snapshot.hasData && snapshot.data != null && snapshot.data!['token'] != null) {
            final userData = snapshot.data!;
            final userIdentifier = userData['email'] ?? userData['username'] ?? '';
            final isSuperuser = userData['isSuperuser'] == 'true';
            return MainTabsScreen(
              userId: userData['id']!,
              userEmail: userIdentifier,
              isSuperuser: isSuperuser,
              onThemeChanged: toggleTheme,
            );
          }

          // Если данных нет - показываем экран входа
          return const LoginScreen();
        },
      ),
    );
  }
}
