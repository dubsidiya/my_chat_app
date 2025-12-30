import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'screens/login_screen.dart';
import 'screens/main_tabs_screen.dart';
import 'services/storage_service.dart';
import 'services/local_messages_service.dart'; // ✅ Импорт сервиса кэширования

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
    // ✅ Инициализируем локальное хранилище перед запуском приложения
    WidgetsFlutterBinding.ensureInitialized();
    await LocalMessagesService.init();
    runApp(MyApp());
  }, (error, stack) {
    if (kDebugMode) {
      print('Uncaught error: $error');
      print('Stack trace: $stack');
    }
  });
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;
  static _MyAppState? _instance;

  @override
  void initState() {
    super.initState();
    _instance = this;
    _loadThemePreference();
  }

  @override
  void dispose() {
    _instance = null;
    super.dispose();
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

  // ✅ Статический метод для обновления темы из любого места
  static void updateTheme(bool isDark) {
    _instance?.toggleTheme(isDark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: Colors.blue.shade700,
        scaffoldBackgroundColor: Colors.grey.shade50,
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blue.shade700, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        primaryColor: Colors.blue.shade300,
        scaffoldBackgroundColor: Colors.grey.shade900,
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.grey.shade800,
          foregroundColor: Colors.white,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          color: Colors.grey.shade800,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade800,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blue.shade300, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
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
                child: Center(
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
            print('✅ Автоматический вход: userId=${userData['id']}, email=${userData['email']}');
            print('✅ Токен найден: ${userData['token']!.substring(0, 20)}...');
            print('✅ Токен полный: ${userData['token']}');
            return MainTabsScreen(
              userId: userData['id']!,
              userEmail: userData['email']!,
              onThemeChanged: toggleTheme, // ✅ Передаем функцию переключения темы
            );
          } else {
            print('⚠️ Автоматический вход не выполнен:');
            print('  - hasData: ${snapshot.hasData}');
            print('  - data: ${snapshot.data}');
            if (snapshot.data != null) {
              print('  - keys: ${snapshot.data!.keys}');
              print('  - token: ${snapshot.data!['token']}');
            } else {
              print('  - snapshot.data is null');
            }
          }

          // Если данных нет - показываем экран входа
          return LoginScreen();
        },
      ),
    );
  }
}
