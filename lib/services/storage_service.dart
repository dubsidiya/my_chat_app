import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _tokenKey = 'auth_token';
  static const String _isSuperuserKey = 'is_superuser';
  static const String _themeModeKey = 'theme_mode'; // ✅ Ключ для темы
  static const String _soundOnNewMessageKey = 'sound_on_new_message';
  static const String _vibrationOnNewMessageKey = 'vibration_on_new_message';
  static const String _privateUnlockedPrefix = 'private_features_unlocked_';
  static const String _chatOrderPrefix = 'chat_order_';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  // Сохранение данных пользователя
  static Future<void> saveUserData(String userId, String userEmail, String token, {bool isSuperuser = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, userId);
      await prefs.setString(_userEmailKey, userEmail);
      await prefs.setBool(_isSuperuserKey, isSuperuser);
      // Токен: на mobile/desktop — secure storage, на web — shared_preferences
      if (kIsWeb) {
        await prefs.setString(_tokenKey, token);
      } else {
        await _secure.write(key: _tokenKey, value: token);
        // Удаляем возможный старый токен из prefs (миграция)
        await prefs.remove(_tokenKey);
      }
    } catch (e) {
      if (kDebugMode) {
        // Не логируем токен/PII
        // ignore: avoid_print
        print('StorageService.saveUserData error: $e');
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
      final token = await getToken();

      if (userId != null && userEmail != null && token != null) {
        final isSuperuser = prefs.getBool(_isSuperuserKey) ?? false;
        return {
          'id': userId,
          'email': userEmail,
          'token': token,
          'isSuperuser': isSuperuser.toString(),
        };
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.getUserData error: $e');
      }
      return null;
    }
  }

  // Получение токена
  static Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (kIsWeb) {
        return prefs.getString(_tokenKey);
      }
      final token = await _secure.read(key: _tokenKey);
      // Фоллбек/миграция со старой версии
      if (token == null) {
        final legacy = prefs.getString(_tokenKey);
        if (legacy != null && legacy.isNotEmpty) {
          await _secure.write(key: _tokenKey, value: legacy);
          await prefs.remove(_tokenKey);
          return legacy;
        }
      }
      return token;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.getToken error: $e');
      }
      return null;
    }
  }

  // Очистка данных пользователя (при выходе)
  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_userIdKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_isSuperuserKey);
    if (!kIsWeb) {
      await _secure.delete(key: _tokenKey);
    }
    if (userId != null) {
      await prefs.remove('$_privateUnlockedPrefix$userId');
      await prefs.remove('$_chatOrderPrefix$userId');
    }
  }

  /// Сохранить порядок чатов (список id чатов).
  static Future<void> saveChatOrder(String userId, List<String> chatIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_chatOrderPrefix$userId', jsonEncode(chatIds));
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.saveChatOrder error: $e');
      }
    }
  }

  /// Загрузить сохранённый порядок чатов.
  static Future<List<String>> getChatOrder(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_chatOrderPrefix$userId');
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map((e) => e.toString()).toList();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.getChatOrder error: $e');
      }
      return [];
    }
  }

  // ✅ Приватные вкладки: сохранение доступа (по userId)
  static Future<void> setPrivateFeaturesUnlocked(String userId, bool unlocked) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_privateUnlockedPrefix$userId', unlocked);
  }

  // ✅ Приватные вкладки: проверка доступа (по userId)
  static Future<bool> isPrivateFeaturesUnlocked(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_privateUnlockedPrefix$userId') ?? false;
  }
  
  // ✅ Сохранение режима темы
  static Future<void> saveThemeMode(bool isDark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_themeModeKey, isDark);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.saveThemeMode error: $e');
      }
    }
  }
  
  // ✅ Получение режима темы
  static Future<bool> getThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_themeModeKey) ?? false; // По умолчанию светлая тема
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.getThemeMode error: $e');
      }
      return false;
    }
  }

  /// Звук при новом сообщении (по умолчанию вкл)
  static Future<void> setSoundOnNewMessage(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_soundOnNewMessageKey, enabled);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.setSoundOnNewMessage error: $e');
      }
    }
  }

  static Future<bool> getSoundOnNewMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_soundOnNewMessageKey) ?? true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.getSoundOnNewMessage error: $e');
      }
      return true;
    }
  }

  /// Вибрация при новом сообщении (по умолчанию вкл)
  static Future<void> setVibrationOnNewMessage(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_vibrationOnNewMessageKey, enabled);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.setVibrationOnNewMessage error: $e');
      }
    }
  }

  static Future<bool> getVibrationOnNewMessage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_vibrationOnNewMessageKey) ?? true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.getVibrationOnNewMessage error: $e');
      }
      return true;
    }
  }
}

