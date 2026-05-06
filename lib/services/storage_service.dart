import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const String _userIdKey = 'user_id';
  static const String _userEmailKey = 'user_email';
  static const String _displayNameKey = 'display_name';
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _isSuperuserKey = 'is_superuser';
  static const String _avatarUrlKey = 'avatar_url';
  static const String _soundOnNewMessageKey = 'sound_on_new_message';
  static const String _vibrationOnNewMessageKey = 'vibration_on_new_message';
  static const String _privateUnlockedPrefix = 'private_features_unlocked_';
  static const String _chatOrderPrefix = 'chat_order_';
  static const String _eulaAcceptedPrefix = 'eula_accepted_';
  static const String _hiddenStudentsPrefix = 'hidden_students_';
  static const String _themeVariantKey = 'theme_variant';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  // Сохранение данных пользователя (userEmail = логин для входа)
  static Future<void> saveUserData(
    String userId,
    String userEmail,
    String token, {
    String? refreshToken,
    bool isSuperuser = false,
    String? displayName,
    String? avatarUrl,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userIdKey, userId);
      await prefs.setString(_userEmailKey, userEmail);
      if (displayName != null) {
        await prefs.setString(_displayNameKey, displayName);
      } else {
        await prefs.remove(_displayNameKey);
      }
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        await prefs.setString(_avatarUrlKey, avatarUrl);
      } else {
        await prefs.remove(_avatarUrlKey);
      }
      await prefs.setBool(_isSuperuserKey, isSuperuser);
      // Токен: на mobile/desktop — secure storage; на web — SharedPreferences (риск XSS:
      // при уязвимости XSS токен может быть прочитан скриптом; для высоких требований
      // рассмотреть httpOnly cookie на бэкенде).
      if (kIsWeb) {
        await prefs.setString(_tokenKey, token);
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await prefs.setString(_refreshTokenKey, refreshToken);
        }
      } else {
        await _secure.write(key: _tokenKey, value: token);
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await _secure.write(key: _refreshTokenKey, value: refreshToken);
        }
        // Удаляем возможный старый токен из prefs (миграция)
        await prefs.remove(_tokenKey);
        await prefs.remove(_refreshTokenKey);
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
        final displayName = prefs.getString(_displayNameKey);
        final avatarUrl = prefs.getString(_avatarUrlKey);
        return {
          'id': userId,
          'email': userEmail,
          'token': token,
          if ((await getRefreshToken()) != null) 'refreshToken': (await getRefreshToken())!,
          'isSuperuser': isSuperuser.toString(),
          if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
          if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
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

  static Future<String?> getRefreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (kIsWeb) {
        return prefs.getString(_refreshTokenKey);
      }
      final token = await _secure.read(key: _refreshTokenKey);
      if (token == null) {
        final legacy = prefs.getString(_refreshTokenKey);
        if (legacy != null && legacy.isNotEmpty) {
          await _secure.write(key: _refreshTokenKey, value: legacy);
          await prefs.remove(_refreshTokenKey);
          return legacy;
        }
      }
      return token;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setRefreshToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_refreshTokenKey);
      if (!kIsWeb) await _secure.delete(key: _refreshTokenKey);
      return;
    }
    if (kIsWeb) {
      await prefs.setString(_refreshTokenKey, token);
    } else {
      await _secure.write(key: _refreshTokenKey, value: token);
      await prefs.remove(_refreshTokenKey);
    }
  }

  /// URL аватара текущего пользователя (кэш)
  static Future<void> setAvatarUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.isEmpty) {
      await prefs.remove(_avatarUrlKey);
    } else {
      await prefs.setString(_avatarUrlKey, url);
    }
  }

  static Future<String?> getAvatarUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_avatarUrlKey);
  }

  // Очистка данных пользователя (при выходе)
  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_userIdKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_avatarUrlKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_isSuperuserKey);
    if (!kIsWeb) {
      await _secure.delete(key: _tokenKey);
      await _secure.delete(key: _refreshTokenKey);
    }
    if (userId != null) {
      await prefs.remove('$_privateUnlockedPrefix$userId');
      // Порядок чатов не удаляем при выходе — при повторном входе под тем же userId порядок сохранится.
      await prefs.remove('$_eulaAcceptedPrefix$userId');
    }
  }

  static Future<void> setEulaAccepted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_eulaAcceptedPrefix$userId', true);
  }

  static Future<bool> getEulaAccepted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_eulaAcceptedPrefix$userId') ?? false;
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

  /// Ник (как тебя видят другие). null = показывать логин.
  static Future<void> setDisplayName(String? displayName) async {
    final prefs = await SharedPreferences.getInstance();
    if (displayName == null || displayName.isEmpty) {
      await prefs.remove(_displayNameKey);
    } else {
      await prefs.setString(_displayNameKey, displayName);
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

  /// Локально скрытые ученики (по userId). Не удаляет ученика на сервере.
  static Future<Set<int>> getHiddenStudentIds(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_hiddenStudentsPrefix$userId');
      if (raw == null || raw.isEmpty) return <int>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <int>{};
      return decoded
          .map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .where((id) => id > 0)
          .toSet();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.getHiddenStudentIds error: $e');
      }
      return <int>{};
    }
  }

  static Future<void> setHiddenStudentIds(String userId, Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalized = ids.where((id) => id > 0).toSet().toList()..sort();
      await prefs.setString('$_hiddenStudentsPrefix$userId', jsonEncode(normalized));
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.setHiddenStudentIds error: $e');
      }
    }
  }

  /// Сохранённое имя темы (storageKey AppThemeVariant). null = тема по умолчанию.
  static Future<String?> getThemeVariantRaw() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_themeVariantKey);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.getThemeVariantRaw error: $e');
      }
      return null;
    }
  }

  static Future<void> setThemeVariantRaw(String storageKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeVariantKey, storageKey);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('StorageService.setThemeVariantRaw error: $e');
      }
    }
  }

  static Future<void> hideStudent(String userId, int studentId) async {
    final ids = await getHiddenStudentIds(userId);
    ids.add(studentId);
    await setHiddenStudentIds(userId, ids);
  }

  static Future<void> unhideStudent(String userId, int studentId) async {
    final ids = await getHiddenStudentIds(userId);
    ids.remove(studentId);
    await setHiddenStudentIds(userId, ids);
  }
}

