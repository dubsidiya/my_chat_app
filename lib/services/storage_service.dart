import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _tokenKey = 'auth_token';

  // Сохранение данных пользователя
  static Future<void> saveUserData(String userId, String userEmail, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userEmailKey, userEmail);
    await prefs.setString(_tokenKey, token);
  }

  // Получение данных пользователя
  static Future<Map<String, String>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_userIdKey);
    final userEmail = prefs.getString(_userEmailKey);
    final token = prefs.getString(_tokenKey);

    if (userId != null && userEmail != null && token != null) {
      return {
        'id': userId,
        'email': userEmail,
        'token': token,
      };
    }
    return null;
  }

  // Получение токена
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // Очистка данных пользователя (при выходе)
  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_tokenKey);
  }
}

