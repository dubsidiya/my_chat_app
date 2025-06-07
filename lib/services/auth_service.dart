import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  final String baseUrl = 'http://localhost:10000'; // Или твой реальный URL сервера

  Future<String?> registerUser(String email, String password) async {
    final url = Uri.parse('$baseUrl/register');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 201) {
        return null; // Регистрация успешна
      } else {
        final data = jsonDecode(response.body);
        return data['message'] ?? 'Ошибка при регистрации';
      }
    } catch (e) {
      return 'Ошибка подключения к серверу';
    }
  }

  Future<String?> loginUser(String email, String password) async {
    final url = Uri.parse('$baseUrl/login');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        return null; // Вход успешен
      } else {
        final data = jsonDecode(response.body);
        return data['message'] ?? 'Ошибка входа';
      }
    } catch (e) {
      return 'Ошибка подключения к серверу';
    }
  }
}
