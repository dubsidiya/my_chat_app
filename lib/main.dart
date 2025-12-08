import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/storage_service.dart';

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
    runApp(MyApp());
  }, (error, stack) {
    if (kDebugMode) {
      print('Uncaught error: $error');
      print('Stack trace: $stack');
    }
  });
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      theme: ThemeData(primarySwatch: Colors.red),
      home: FutureBuilder<Map<String, String>?>(
        future: StorageService.getUserData(),
        builder: (context, snapshot) {
          // Показываем загрузку пока проверяем сохраненные данные
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Если есть сохраненные данные - автоматически входим
          if (snapshot.hasData && snapshot.data != null) {
            final userData = snapshot.data!;
            return HomeScreen(
              userId: userData['id']!,
              userEmail: userData['email']!,
            );
          }

          // Если данных нет - показываем экран входа
          return LoginScreen();
        },
      ),
    );
  }
}
