import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';
import '../utils/timed_http.dart';
import 'storage_service.dart';

/// Простое шифрование сообщений на общем ключе чата (shared key).
///
/// Модель: сервер генерирует один AES-256 ключ на чат и выдаёт его участникам
/// (`GET /chats/:id/key`). Клиент шифрует/расшифровывает им текст и медиа.
/// Это НЕ end-to-end шифрование (ключ хранится на сервере) — это защита
/// содержимого в БД «от посторонних глаз». Здесь нет X25519, обмена ключами,
/// ротации и ожиданий ключа от собеседника.
class ChatKeyService {
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static const String _keyPrefix = 'chat_shared_key_';
  static const int _macLen = 16; // AES-GCM auth tag

  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Map<String, SecretKey> _memCache = <String, SecretKey>{};

  static String _cacheKey(String chatId) => '$_keyPrefix$chatId';

  /// Получить ключ чата: память → secure storage → сервер. null при недоступности.
  static Future<SecretKey?> getChatKey(String chatId) async {
    final cachedMem = _memCache[chatId];
    if (cachedMem != null) return cachedMem;

    final stored = await _secure.read(key: _cacheKey(chatId));
    if (stored != null && stored.isNotEmpty) {
      final key = SecretKey(base64Decode(stored));
      _memCache[chatId] = key;
      return key;
    }

    final fetched = await _fetchKeyFromServer(chatId);
    if (fetched == null) return null;
    final bytes = base64Decode(fetched);
    await _secure.write(key: _cacheKey(chatId), value: fetched);
    final key = SecretKey(bytes);
    _memCache[chatId] = key;
    return key;
  }

  static Future<String?> _fetchKeyFromServer(String chatId) async {
    final token = await StorageService.getToken();
    if (token == null) return null;
    try {
      final resp = await timedGet(
        Uri.parse('${ApiConfig.baseUrl}/chats/$chatId/key'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final keyB64 = data['key'] as String?;
      if (keyB64 == null || keyB64.isEmpty) return null;
      return keyB64;
    } catch (_) {
      return null;
    }
  }

  // ─── Текст ───

  /// Шифрует текст. Возвращает JSON-строку `{v,ct,n}` или null, если ключ недоступен.
  static Future<String?> encryptText(String chatId, String plaintext) async {
    if (plaintext.isEmpty) return null;
    final key = await getChatKey(chatId);
    if (key == null) return null;
    final nonce = _aesGcm.newNonce();
    final box = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'v': '1',
      'ct': base64Encode(box.cipherText + box.mac.bytes),
      'n': base64Encode(nonce),
    });
  }

  /// Расшифровывает текст. Возвращает открытый текст или null, если расшифровать
  /// нельзя (нет ключа / чужой формат / повреждено / legacy-чат).
  static Future<String?> decryptText(String chatId, String content) async {
    if (!isEncryptedText(content)) return content;
    try {
      final data = jsonDecode(content) as Map<String, dynamic>;
      final ct = base64Decode(data['ct'] as String);
      final nonce = base64Decode(data['n'] as String);
      final key = await getChatKey(chatId);
      if (key == null) return null;
      final plain = await _decrypt(ct, nonce, key);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// Похоже ли содержимое на зашифрованный JSON `{v:'1', ct, n}`.
  static bool isEncryptedText(String content) {
    if (!content.startsWith('{')) return false;
    try {
      final data = jsonDecode(content);
      return data is Map && data['v'] == '1' && data['ct'] != null;
    } catch (_) {
      return false;
    }
  }

  // ─── Медиа (байты) ───

  /// Шифрует байты медиа. Возвращает JSON `{v,ct,n}` в utf8 или null, если ключ недоступен.
  static Future<Uint8List?> encryptBytes(String chatId, Uint8List plainBytes) async {
    if (plainBytes.isEmpty) return null;
    final key = await getChatKey(chatId);
    if (key == null) return null;
    final nonce = _aesGcm.newNonce();
    final box = await _aesGcm.encrypt(plainBytes, secretKey: key, nonce: nonce);
    final map = {
      'v': '1',
      'ct': base64Encode(box.cipherText + box.mac.bytes),
      'n': base64Encode(nonce),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  /// Расшифровывает байты медиа. null, если это не наш формат или ключа нет.
  static Future<Uint8List?> decryptBytes(String chatId, Uint8List encryptedBytes) async {
    try {
      if (!looksLikeEncryptedBytes(encryptedBytes)) return null;
      final s = utf8.decode(encryptedBytes);
      final data = jsonDecode(s) as Map<String, dynamic>;
      final ct = base64Decode(data['ct'] as String);
      final nonce = base64Decode(data['n'] as String);
      final key = await getChatKey(chatId);
      if (key == null) return null;
      final plain = await _decrypt(ct, nonce, key);
      return Uint8List.fromList(plain);
    } catch (_) {
      return null;
    }
  }

  /// Быстрая проверка: байты выглядят как зашифрованный JSON.
  static bool looksLikeEncryptedBytes(Uint8List bytes) {
    if (bytes.length < 10) return false;
    try {
      final head = utf8.decode(bytes.sublist(0, bytes.length > 50 ? 50 : bytes.length));
      return head.startsWith('{') && head.contains('"v"') && head.contains('"ct"');
    } catch (_) {
      return false;
    }
  }

  static Future<List<int>> _decrypt(Uint8List ct, List<int> nonce, SecretKey key) async {
    final cipherText = ct.sublist(0, ct.length - _macLen);
    final mac = Mac(ct.sublist(ct.length - _macLen));
    return _aesGcm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
  }

  /// Очистить кэш ключей (logout / удаление аккаунта).
  static Future<void> clearAll() async {
    _memCache.clear();
    try {
      final all = await _secure.readAll();
      for (final k in all.keys) {
        if (k.startsWith(_keyPrefix)) {
          await _secure.delete(key: k);
        }
      }
    } catch (_) {}
  }
}
