import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';

  // Сохранение данных пользователя
  static Future<void> saveUserData(String userId, String userEmail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userEmailKey, userEmail);
  }

  // Получение данных пользователя
  static Future<Map<String, String>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_userIdKey);
    final userEmail = prefs.getString(_userEmailKey);

    if (userId != null && userEmail != null) {
      return {
        'id': userId,
        'email': userEmail,
      };
    }
    return null;
  }

  // Очистка данных пользователя (при выходе)
  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
  }
}

