import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class StorageService {
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _tokenKey = 'auth_token';

  // Сохранение данных пользователя
  static Future<void> saveUserData(String userId, String userEmail, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, userId);
      await prefs.setString(_userEmailKey, userEmail);
      await prefs.setString(_tokenKey, token);
      print('✅ Токен сохранен в SharedPreferences: ${token.substring(0, 20)}...');
      if (kIsWeb) {
        print('✅ Платформа: WEB - данные сохранены');
        print('   Проверьте в DevTools: Application → Local Storage → flutter.auth_token');
      }
    } catch (e) {
      print('❌ Ошибка сохранения токена: $e');
      if (kIsWeb) {
        print('   Платформа: WEB - возможно проблема с SharedPreferences на веб');
      }
      rethrow;
    }
  }

  // Получение данных пользователя
  static Future<Map<String, String>?> getUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_userIdKey);
      final userEmail = prefs.getString(_userEmailKey);
      final token = prefs.getString(_tokenKey);

      print('🔍 getUserData:');
      print('   userId: $userId');
      print('   userEmail: $userEmail');
      print('   token: ${token != null ? token.substring(0, 20) + "..." : "НЕ НАЙДЕН"}');

      if (userId != null && userEmail != null && token != null) {
        print('✅ Все данные найдены, возвращаем Map');
        return {
          'id': userId,
          'email': userEmail,
          'token': token,
        };
      } else {
        print('⚠️ Не все данные найдены:');
        print('   userId: ${userId != null ? "есть" : "НЕТ"}');
        print('   userEmail: ${userEmail != null ? "есть" : "НЕТ"}');
        print('   token: ${token != null ? "есть" : "НЕТ"}');
      }
      return null;
    } catch (e) {
      print('❌ Ошибка getUserData: $e');
      return null;
    }
  }

  // Получение токена
  static Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token != null) {
        print('✅ Токен получен из SharedPreferences: ${token.substring(0, 20)}...');
        if (kIsWeb) {
          print('   Платформа: WEB');
        }
      } else {
        print('⚠️ Токен не найден в SharedPreferences');
        if (kIsWeb) {
          print('⚠️ Платформа: WEB - проверьте localStorage в DevTools (Application → Local Storage)');
          print('   Ищите ключ: flutter.auth_token');
        }
      }
      return token;
    } catch (e) {
      print('❌ Ошибка получения токена: $e');
      if (kIsWeb) {
        print('   Платформа: WEB - возможно проблема с SharedPreferences на веб');
      }
      return null;
    }
  }

  // Очистка данных пользователя (при выходе)
  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_tokenKey);
  }
}

