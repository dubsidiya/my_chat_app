import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const String baseUrl = 'https://my-server-chat.onrender.com';

  static Future<String?> register(String email, String password) async {
    final url = Uri.parse('$baseUrl/register');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 201) {
      return null;
    } else {
      final data = jsonDecode(response.body);
      return data['message'] ?? 'Ошибка регистрации';
    }
  }

  static Future<String?> login(String email, String password) async {
    final url = Uri.parse('$baseUrl/login');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      return null;
    } else {
      final data = jsonDecode(response.body);
      return data['message'] ?? 'Ошибка входа';
    }
  }
}
