import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode;
import '../config/api_config.dart';
import 'storage_service.dart';

class AuthService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<Map<String, dynamic>?> loginUser(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Сохраняем токен
        if (data['token'] != null) {
          // Используем username из ответа, если есть, иначе email (для обратной совместимости)
          final userIdentifier = data['username'] ?? data['email'] ?? '';
          await StorageService.saveUserData(
            data['id'].toString(),
            userIdentifier,
            data['token'],
          );
          // При обычном логине приватный доступ не выдаем (требуется отдельная разблокировка)
          await StorageService.setPrivateFeaturesUnlocked(data['id'].toString(), false);
        }
        return data;
      } else if (response.statusCode == 500) {
        // Пробуем распарсить сообщение об ошибке
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ?? 'Ошибка сервера (500)');
        } catch (e) {
          throw Exception('Ошибка сервера (500). Проверьте состояние базы данных на сервере.');
        }
      } else if (response.statusCode == 401) {
        throw Exception('Неверный логин или пароль');
      } else {
        throw Exception('Ошибка подключения к серверу (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Ошибка сети: $e');
    }
  }

  Future<bool> registerUser(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        // Сохраняем токен
        if (data['token'] != null) {
          // Используем username из ответа, если есть, иначе email (для обратной совместимости)
          final userIdentifier = data['username'] ?? data['email'] ?? '';
          await StorageService.saveUserData(
            data['userId'].toString(),
            userIdentifier,
            data['token'],
          );
          // Новые аккаунты не имеют приватного доступа по умолчанию
          await StorageService.setPrivateFeaturesUnlocked(data['userId'].toString(), false);
        }
        return true;
      } else if (response.statusCode == 400) {
        // Пробуем распарсить сообщение об ошибке
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ?? 'Ошибка регистрации');
        } catch (e) {
          if (e is Exception) {
            rethrow;
          }
          throw Exception('Ошибка регистрации');
        }
      } else if (response.statusCode == 500) {
        // Пробуем распарсить сообщение об ошибке
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ?? 'Ошибка сервера (500)');
        } catch (e) {
          throw Exception('Ошибка сервера (500). Проверьте состояние базы данных на сервере.');
        }
      } else {
        throw Exception('Ошибка подключения к серверу (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Ошибка сети: $e');
    }
  }

  Future<void> deleteAccount(String userId, String password) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        throw Exception('Требуется авторизация');
      }

      final url = Uri.parse('$baseUrl/auth/user/$userId');

      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'password': password}),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при удалении аккаунта');
        },
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 401) {
        String errorMessage = 'Неверный пароль';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      } else if (response.statusCode == 400) {
        String errorMessage = 'Неверный запрос';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      } else {
        String errorMessage = 'Не удалось удалить аккаунт';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          errorMessage = 'Ошибка сервера (${response.statusCode})';
        }
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      if (kDebugMode) {
        // ignore: avoid_print
        print('AuthService.deleteAccount unexpected error: $e');
      }
      throw Exception('Неожиданная ошибка при удалении аккаунта: $e');
    }
  }

  Future<void> changePassword(String userId, String oldPassword, String newPassword) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        throw Exception('Требуется авторизация');
      }

      final url = Uri.parse('$baseUrl/auth/user/$userId/password');

      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при смене пароля');
        },
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 401) {
        String errorMessage = 'Неверный текущий пароль';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      } else if (response.statusCode == 400) {
        String errorMessage = 'Неверный запрос';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      } else {
        String errorMessage = 'Не удалось изменить пароль';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMessage = errorData['message'];
          }
        } catch (_) {
          errorMessage = 'Ошибка сервера (${response.statusCode})';
        }
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      if (kDebugMode) {
        // ignore: avoid_print
        print('AuthService.changePassword unexpected error: $e');
      }
      throw Exception('Неожиданная ошибка при смене пароля: $e');
    }
  }

  /// Запрос кода сброса пароля (по логину)
  /// Возвращает resetToken если пользователь найден, иначе null
  Future<Map<String, dynamic>> requestPasswordReset(String username) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/request-password-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username.trim()}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      }
      try {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Ошибка запроса');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Ошибка запроса сброса пароля');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Ошибка сети: $e');
    }
  }

  /// Сброс пароля по коду
  Future<void> resetPassword(String token, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token.trim(), 'newPassword': newPassword}),
      );

      if (response.statusCode == 200) return;

      try {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Ошибка сброса');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Ошибка сброса пароля');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Ошибка сети: $e');
    }
  }

  /// Запрос на сервер для получения токена с privateAccess=true
  Future<void> unlockPrivateAccess(String code) async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('Требуется авторизация');
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/unlock-private'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'code': code}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userIdentifier = data['username'] ?? data['email'] ?? '';
        if (data['token'] != null) {
          await StorageService.saveUserData(
            data['id'].toString(),
            userIdentifier.toString(),
            data['token'].toString(),
          );
        }
        return;
      }

      if (response.statusCode == 403) {
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ?? 'Неверный код');
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception('Неверный код');
        }
      }

      if (response.statusCode == 400) {
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ?? 'Неверный запрос');
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception('Неверный запрос');
        }
      }

      if (response.statusCode == 500) {
        try {
          final errorData = jsonDecode(response.body);
          throw Exception(errorData['message'] ?? 'Ошибка сервера (500)');
        } catch (e) {
          throw Exception('Ошибка сервера (500)');
        }
      }

      throw Exception('Ошибка подключения к серверу (${response.statusCode})');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Ошибка сети: $e');
    }
  }

}
