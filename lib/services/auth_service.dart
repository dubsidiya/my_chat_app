import 'dart:convert';
import 'package:http/http.dart' as http;

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
        return jsonDecode(response.body);
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
      Uri.parse('$baseUrl/auth/register'), // <--- ОБРАТИ ВНИМАНИЕ
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    print('REGISTER STATUS: ${response.statusCode}');
    print('REGISTER RESPONSE: ${response.body}');

    return response.statusCode == 201;
  }

}
