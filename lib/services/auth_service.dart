import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class AuthService {
  final String baseUrl = 'https://my-server-chat.onrender.com';

  Future<Map<String, dynamic>?> loginUser(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      print('Login status: ${response.statusCode}');
      print('Login response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Login успешен, получены данные: ${data.keys}');
        // Сохраняем токен
        if (data['token'] != null) {
          print('💾 Сохранение токена...');
          await StorageService.saveUserData(
            data['id'].toString(),
            data['email'],
            data['token'],
          );
          print('✅ Токен сохранен успешно');
        } else {
          print('⚠️ Токен не получен в ответе!');
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
        throw Exception('Неверный email или пароль');
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

  Future<bool> registerUser(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    print('REGISTER STATUS: ${response.statusCode}');
    print('REGISTER RESPONSE: ${response.body}');

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      // Сохраняем токен
      if (data['token'] != null) {
        await StorageService.saveUserData(
          data['userId'].toString(),
          data['email'],
          data['token'],
        );
      }
      return true;
    }
    return false;
  }

  Future<void> deleteAccount(String userId, String password) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        throw Exception('Требуется авторизация');
      }

      final url = Uri.parse('$baseUrl/auth/user/$userId');
      print('Deleting account: $userId');

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

      print('Delete account status: ${response.statusCode}');
      print('Delete account response: ${response.body}');

      if (response.statusCode == 200) {
        print('Account deleted successfully: $userId');
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
        print('Delete account error: ${response.statusCode} - ${response.body}');
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      print('Unexpected error in deleteAccount: $e');
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
      print('Changing password for user: $userId');

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

      print('Change password status: ${response.statusCode}');
      print('Change password response: ${response.body}');

      if (response.statusCode == 200) {
        print('Password changed successfully for user: $userId');
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
        print('Change password error: ${response.statusCode} - ${response.body}');
        throw Exception('$errorMessage (${response.statusCode})');
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      print('Unexpected error in changePassword: $e');
      throw Exception('Неожиданная ошибка при смене пароля: $e');
    }
  }

}
