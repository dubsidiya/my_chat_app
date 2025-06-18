import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  final _baseUrl = 'https://my-server-chat.onrender.com';

  Future<String?> registerUser(String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 201) {
      return null; // успешно
    } else {
      final data = jsonDecode(response.body);
      return data['message'] ?? 'Ошибка регистрации';
    }
  }

  Future<String?> loginUser(String email, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['userId'].toString(); // id пользователя
    } else {
      return null; // ошибка
    }
  }
}
