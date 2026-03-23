import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'storage_service.dart';

/// End-to-end encryption service.
/// Uses X25519 for key agreement + AES-256-GCM for message encryption.
/// Private key encrypted with user's password and backed up on server (PBKDF2 + AES-GCM).
/// On new device: download backup → decrypt with password → restore key pair.
class E2eeService {
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static const String _privateKeyKey = 'e2ee_private_key';
  static const String _publicKeyKey = 'e2ee_public_key';
  static const String _chatKeyPrefix = 'e2ee_chat_key_';

  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );
  static final Map<String, DateTime> _lastRequestChatKeyAt = <String, DateTime>{};
  static bool _publicKeySyncAttemptedThisRun = false;
  static String _chatCacheKey(String chatId, [int? keyVersion]) =>
      keyVersion == null ? '$_chatKeyPrefix$chatId' : '$_chatKeyPrefix${chatId}_v$keyVersion';

  /// Check if local key pair exists.
  static Future<bool> hasLocalKeyPair() async {
    final existing = await _secure.read(key: _privateKeyKey);
    return existing != null && existing.isNotEmpty;
  }

  /// Generate key pair, persist locally, upload public key + encrypted backup to server.
  /// [password] is the user's login password — used to encrypt the private key for backup.
  static Future<void> ensureKeyPair({String? password}) async {
    final existing = await _secure.read(key: _privateKeyKey);
    if (existing != null && existing.isNotEmpty) {
      // Важный кейс: локальная пара уже есть, но public key мог не загрузиться на сервер
      // (например, из-за 429 в предыдущем запуске). Пытаемся синхронизировать хотя бы раз за запуск.
      if (!_publicKeySyncAttemptedThisRun) {
        try {
          final pubB64 = await _secure.read(key: _publicKeyKey);
          if (pubB64 != null && pubB64.isNotEmpty) {
            final uploaded = await _uploadPublicKey(pubB64);
            _publicKeySyncAttemptedThisRun = uploaded;
            if (password != null && password.isNotEmpty) {
              await _uploadKeyBackup(existing, pubB64, password);
            }
          }
        } catch (_) {}
      }
      return;
    }

    if (password != null && password.isNotEmpty) {
      final restored = await _tryRestoreFromBackup(password);
      if (restored) return;
    }

    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    final privB64 = base64Encode(privateBytes);
    final pubB64 = base64Encode(publicKey.bytes);

    await _secure.write(key: _privateKeyKey, value: privB64);
    await _secure.write(key: _publicKeyKey, value: pubB64);

    await _uploadPublicKey(pubB64);

    if (password != null && password.isNotEmpty) {
      await _uploadKeyBackup(privB64, pubB64, password);
    }
  }

  static Future<SimpleKeyPairData> _getKeyPair() async {
    final privB64 = await _secure.read(key: _privateKeyKey);
    final pubB64 = await _secure.read(key: _publicKeyKey);
    if (privB64 == null || pubB64 == null) {
      throw Exception('E2EE key pair not found. Call ensureKeyPair() first.');
    }
    final privBytes = base64Decode(privB64);
    final pubBytes = base64Decode(pubB64);
    return SimpleKeyPairData(
      privBytes,
      publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  static Future<String> getMyPublicKeyBase64() async {
    final pubB64 = await _secure.read(key: _publicKeyKey);
    if (pubB64 == null) throw Exception('E2EE public key not found');
    return pubB64;
  }

  // ─── Chat key management ───

  /// Generate a random AES-256 chat key, encrypt it for each member, and upload.
  static Future<void> createChatKey(
    String chatId,
    List<Map<String, dynamic>> members, {
    int? keyVersion,
  }) async {
    final chatKey = await _aesGcm.newSecretKey();
    final chatKeyBytes = await chatKey.extractBytes();

    await _secure.write(
      key: _chatCacheKey(chatId, keyVersion),
      value: base64Encode(chatKeyBytes),
    );
    // Keep compatibility cache key as pointer to "latest known" key for chat.
    await _secure.write(
      key: _chatCacheKey(chatId),
      value: base64Encode(chatKeyBytes),
    );

    final myKeyPair = await _getKeyPair();
    final myPubB64 = await getMyPublicKeyBase64();

    final List<Map<String, String>> keysPayload = [];
    for (final member in members) {
      final memberPubB64 = member['publicKey'] as String?;
      final memberId = member['id']?.toString();
      if (memberPubB64 == null || memberPubB64.isEmpty || memberId == null) continue;

      final memberPub = SimplePublicKey(base64Decode(memberPubB64), type: KeyPairType.x25519);
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: myKeyPair,
        remotePublicKey: memberPub,
      );
      final derivedKey = await _hkdf.deriveKey(
        secretKey: sharedSecret,
        info: utf8.encode('e2ee-chat-key-$chatId'),
        nonce: const <int>[],
      );

      final nonce = _aesGcm.newNonce();
      final encrypted = await _aesGcm.encrypt(
        Uint8List.fromList(chatKeyBytes),
        secretKey: derivedKey,
        nonce: nonce,
      );

      keysPayload.add({
        'userId': memberId,
        'encryptedKey': base64Encode(encrypted.cipherText + encrypted.mac.bytes),
        'senderPublicKey': myPubB64,
        'nonce': base64Encode(nonce),
      });
    }

    await _storeChatKeysOnServer(chatId, keysPayload, keyVersion: keyVersion);
  }

  /// Retrieve and decrypt the chat key from the server.
  static Future<SecretKey?> getChatKey(String chatId, {int? keyVersion}) async {
    final cached = await _secure.read(key: _chatCacheKey(chatId, keyVersion));
    if (cached != null && cached.isNotEmpty) {
      return SecretKey(base64Decode(cached));
    }

    final token = await StorageService.getToken();
    if (token == null) return null;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/e2ee/chat-key/$chatId').replace(
        queryParameters: {
          if (keyVersion != null) 'keyVersion': keyVersion.toString(),
        },
      );
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final encKeyB64 = data['encryptedKey'] as String?;
      final senderPubB64 = data['senderPublicKey'] as String?;
      final nonceB64 = data['nonce'] as String?;
      if (encKeyB64 == null || senderPubB64 == null || nonceB64 == null) return null;

      final myKeyPair = await _getKeyPair();
      final senderPub = SimplePublicKey(base64Decode(senderPubB64), type: KeyPairType.x25519);
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: myKeyPair,
        remotePublicKey: senderPub,
      );
      final derivedKey = await _hkdf.deriveKey(
        secretKey: sharedSecret,
        info: utf8.encode('e2ee-chat-key-$chatId'),
        nonce: const <int>[],
      );

      final encBytes = base64Decode(encKeyB64);
      final nonce = base64Decode(nonceB64);
      final macLen = 16;
      final cipherText = encBytes.sublist(0, encBytes.length - macLen);
      final mac = Mac(encBytes.sublist(encBytes.length - macLen));

      final decrypted = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: derivedKey,
      );

      final respVersion = data['keyVersion'] is int
          ? (data['keyVersion'] as int)
          : int.tryParse((data['keyVersion'] ?? '').toString());
      final effectiveVersion = keyVersion ?? respVersion;
      await _secure.write(
        key: _chatCacheKey(chatId, effectiveVersion),
        value: base64Encode(decrypted),
      );
      if (keyVersion == null) {
        await _secure.write(
          key: _chatCacheKey(chatId),
          value: base64Encode(decrypted),
        );
      }
      return SecretKey(decrypted);
    } catch (e) {
      return null;
    }
  }

  // ─── Message encryption ───

  static Future<Map<String, String>?> encryptMessage(String chatId, String plaintext) async {
    if (plaintext.isEmpty) return null;
    final key = await getChatKey(chatId);
    if (key == null) return null;

    final nonce = _aesGcm.newNonce();
    final encrypted = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return {
      'ct': base64Encode(encrypted.cipherText + encrypted.mac.bytes),
      'n': base64Encode(nonce),
      'v': '1',
    };
  }

  static Future<String> decryptMessage(String chatId, String encryptedJson, {int? keyVersion}) async {
    try {
      final data = jsonDecode(encryptedJson);
      if (data is! Map || data['v'] != '1') return _cannotDecryptLabel;
      final ct = base64Decode(data['ct'] as String);
      final nonce = base64Decode(data['n'] as String);
      final key = await getChatKey(chatId, keyVersion: keyVersion);
      if (key == null) return _cannotDecryptLabel;

      const macLen = 16;
      final cipherText = ct.sublist(0, ct.length - macLen);
      final mac = Mac(ct.sublist(ct.length - macLen));

      final decrypted = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
      );
      return utf8.decode(decrypted);
    } catch (_) {
      return _cannotDecryptLabel;
    }
  }

  static const String _cannotDecryptLabel = '[зашифровано]';

  /// Шифрование произвольных байт (медиа). Возвращает JSON-строку { v, ct, n } в utf8.
  static Future<Uint8List?> encryptBytes(String chatId, Uint8List plainBytes, {int? keyVersion}) async {
    if (plainBytes.isEmpty) return null;
    final key = await getChatKey(chatId, keyVersion: keyVersion);
    if (key == null) return null;
    final nonce = _aesGcm.newNonce();
    final encrypted = await _aesGcm.encrypt(plainBytes, secretKey: key, nonce: nonce);
    final map = {
      'v': '1',
      'ct': base64Encode(encrypted.cipherText + encrypted.mac.bytes),
      'n': base64Encode(nonce),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  /// Расшифровка байт (медиа). [encryptedBytes] — JSON { v, ct, n } в utf8 или сырые байты (вернёт null).
  static Future<Uint8List?> decryptBytes(String chatId, Uint8List encryptedBytes, {int? keyVersion}) async {
    try {
    final s = utf8.decode(encryptedBytes);
    if (!s.startsWith('{')) return null;
    final data = jsonDecode(s);
    if (data is! Map || data['v'] != '1') return null;
    final ct = base64Decode(data['ct'] as String);
    final nonce = base64Decode(data['n'] as String);
    final key = await getChatKey(chatId, keyVersion: keyVersion);
    if (key == null) return null;
    const macLen = 16;
    final cipherText = ct.sublist(0, ct.length - macLen);
    final mac = Mac(ct.sublist(ct.length - macLen));
    final decrypted = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return Uint8List.fromList(decrypted);
    } catch (_) {
      return null;
    }
  }

  /// Проверка: байты выглядят как E2EE JSON.
  static bool looksLikeEncryptedBytes(Uint8List bytes) {
    if (bytes.length < 10) return false;
    final s = utf8.decode(bytes.sublist(0, bytes.length > 50 ? 50 : bytes.length));
    return s.startsWith('{') && s.contains('"v"') && s.contains('"ct"');
  }

  /// Check if a string looks like an E2EE encrypted message.
  static bool isEncrypted(String content) {
    if (!content.startsWith('{')) return false;
    try {
      final data = jsonDecode(content);
      return data is Map && data['v'] == '1' && data['ct'] != null;
    } catch (_) {
      return false;
    }
  }

  // ─── Private helpers ───

  static Future<bool> _uploadPublicKey(String publicKeyB64) async {
    final token = await StorageService.getToken();
    if (token == null) return false;
    try {
      var resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/e2ee/public-key'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'publicKey': publicKeyB64}),
      );
      // При burst/429 делаем одну отложенную попытку.
      if (resp.statusCode == 429) {
        await Future<void>.delayed(const Duration(seconds: 3));
        resp = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/e2ee/public-key'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'publicKey': publicKeyB64}),
        );
      }
      return resp.statusCode == 200 || resp.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _storeChatKeysOnServer(String chatId, List<Map<String, String>> keys, {int? keyVersion}) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/e2ee/chat-keys'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'chatId': chatId, 'keys': keys, if (keyVersion != null) 'keyVersion': keyVersion}),
    );
  }

  /// Запросить ключ чата у других участников (мы без ключа, например вошли по инвайту). Сервер шлёт им WS e2ee_request_key.
  static Future<void> requestChatKey(String chatId, {int? keyVersion}) async {
    final now = DateTime.now();
    final requestKey = '$chatId:${keyVersion ?? 0}';
    final last = _lastRequestChatKeyAt[requestKey];
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _lastRequestChatKeyAt[requestKey] = now;
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/e2ee/chat/$chatId/request-key'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({if (keyVersion != null) 'keyVersion': keyVersion}),
      );
      if (resp.statusCode != 200 && resp.statusCode != 204) {
        // Не бросаем — вызывающий может опросить ключ позже
      }
    } catch (_) {}
  }

  /// Участники чата без ключа (например, вошли по инвайту). Нужны для shareChatKeyWithNewMembers.
  static Future<List<String>> getMembersWithoutChatKey(String chatId) async {
    final token = await StorageService.getToken();
    if (token == null) return [];
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/e2ee/chat/$chatId/members-without-key'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      final list = data['userIds'] as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Если у нас есть ключ чата — шифруем его для участников без ключа и отправляем на сервер (участники по инвайту смогут расшифровать).
  /// Вызывать при открытии чата после успешной загрузки сообщений.
  static Future<void> shareChatKeyWithNewMembers(String chatId) async {
    final withoutKey = await getMembersWithoutChatKey(chatId);
    if (withoutKey.isEmpty) return;
    final chatKeyB64 = await _secure.read(key: '$_chatKeyPrefix$chatId');
    if (chatKeyB64 == null || chatKeyB64.isEmpty) return;
    final chatKeyBytes = base64Decode(chatKeyB64);
    final pubKeys = await fetchPublicKeys(withoutKey);
    if (pubKeys.isEmpty) return;
    final myKeyPair = await _getKeyPair();
    final myPubB64 = await getMyPublicKeyBase64();
    final List<Map<String, String>> keysPayload = [];
    for (final memberId in withoutKey) {
      final memberPubB64 = pubKeys[memberId];
      if (memberPubB64 == null || memberPubB64.isEmpty) continue;
      try {
        final memberPub = SimplePublicKey(base64Decode(memberPubB64), type: KeyPairType.x25519);
        final sharedSecret = await _x25519.sharedSecretKey(
          keyPair: myKeyPair,
          remotePublicKey: memberPub,
        );
        final derivedKey = await _hkdf.deriveKey(
          secretKey: sharedSecret,
          info: utf8.encode('e2ee-chat-key-$chatId'),
          nonce: const <int>[],
        );
        final nonce = _aesGcm.newNonce();
        final encrypted = await _aesGcm.encrypt(
          Uint8List.fromList(chatKeyBytes),
          secretKey: derivedKey,
          nonce: nonce,
        );
        keysPayload.add({
          'userId': memberId,
          'encryptedKey': base64Encode(encrypted.cipherText + encrypted.mac.bytes),
          'senderPublicKey': myPubB64,
          'nonce': base64Encode(nonce),
        });
      } catch (_) {
        continue;
      }
    }
    if (keysPayload.isNotEmpty) {
      await _storeChatKeysOnServer(chatId, keysPayload);
    }
  }

  /// Адресная отправка ключа конкретным пользователям (используем для WS e2ee_request_key,
  /// чтобы не делать лишний GET members-without-key под rate limit).
  static Future<void> shareChatKeyWithUsers(String chatId, List<String> userIds, {int? keyVersion}) async {
    if (userIds.isEmpty) return;
    final chatKeyB64 = await _secure.read(key: _chatCacheKey(chatId, keyVersion)) ?? await _secure.read(key: _chatCacheKey(chatId));
    if (chatKeyB64 == null || chatKeyB64.isEmpty) return;
    final chatKeyBytes = base64Decode(chatKeyB64);
    final pubKeys = await fetchPublicKeys(userIds);
    if (pubKeys.isEmpty) return;

    final myKeyPair = await _getKeyPair();
    final myPubB64 = await getMyPublicKeyBase64();
    final List<Map<String, String>> keysPayload = [];
    for (final memberId in userIds) {
      final memberPubB64 = pubKeys[memberId];
      if (memberPubB64 == null || memberPubB64.isEmpty) continue;
      try {
        final memberPub = SimplePublicKey(base64Decode(memberPubB64), type: KeyPairType.x25519);
        final sharedSecret = await _x25519.sharedSecretKey(
          keyPair: myKeyPair,
          remotePublicKey: memberPub,
        );
        final derivedKey = await _hkdf.deriveKey(
          secretKey: sharedSecret,
          info: utf8.encode('e2ee-chat-key-$chatId'),
          nonce: const <int>[],
        );
        final nonce = _aesGcm.newNonce();
        final encrypted = await _aesGcm.encrypt(
          Uint8List.fromList(chatKeyBytes),
          secretKey: derivedKey,
          nonce: nonce,
        );
        keysPayload.add({
          'userId': memberId,
          'encryptedKey': base64Encode(encrypted.cipherText + encrypted.mac.bytes),
          'senderPublicKey': myPubB64,
          'nonce': base64Encode(nonce),
        });
      } catch (_) {
        continue;
      }
    }
    if (keysPayload.isNotEmpty) {
      await _storeChatKeysOnServer(chatId, keysPayload, keyVersion: keyVersion);
    }
  }

  static Future<List<Map<String, dynamic>>> getPendingKeyRequests(String chatId) async {
    final token = await StorageService.getToken();
    if (token == null) return [];
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/e2ee/chat/$chatId/key-requests'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = (data['requests'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> processPendingKeyRequests(String chatId) async {
    final pending = await getPendingKeyRequests(chatId);
    if (pending.isEmpty) return;
    final byVersion = <int, List<String>>{};
    for (final r in pending) {
      final uid = r['requesterUserId']?.toString();
      final v = r['keyVersion'] is int ? r['keyVersion'] as int : int.tryParse((r['keyVersion'] ?? '1').toString()) ?? 1;
      if (uid == null || uid.isEmpty) continue;
      byVersion.putIfAbsent(v, () => <String>[]).add(uid);
    }
    for (final entry in byVersion.entries) {
      await shareChatKeyWithUsers(chatId, entry.value.toSet().toList(), keyVersion: entry.key);
    }
  }

  /// Fetch public keys of given user IDs from the server.
  static Future<Map<String, String?>> fetchPublicKeys(List<String> userIds) async {
    final token = await StorageService.getToken();
    if (token == null) return {};
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/e2ee/public-keys'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'userIds': userIds}),
      );
      if (resp.statusCode != 200) return {};
      final data = jsonDecode(resp.body);
      final raw = data['keys'];
      if (raw is! Map) return {};
      // JSON-ключи из Node/pg могут прийти как int в Dart — всегда нормализуем в String.
      return raw.map<String, String?>(
        (k, v) => MapEntry(k.toString(), v?.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  /// После [requestChatKey] другие клиенты по WS выкладывают ключ на сервер.
  /// Периодически запрашиваем GET /e2ee/chat-key, пока ключ не появится (кэш локально пуст при 404).
  static Future<bool> waitForChatKeyFromServer(
    String chatId, {
    int? keyVersion,
    Duration timeout = const Duration(seconds: 18),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var attempt = 0;
    while (DateTime.now().isBefore(deadline)) {
      final k = await getChatKey(chatId, keyVersion: keyVersion);
      if (k != null) return true;
      attempt += 1;
      final mult = attempt < 3 ? 1 : (attempt < 6 ? 2 : 3);
      final baseDelayMs = interval.inMilliseconds * mult;
      final jitterMs = (DateTime.now().microsecondsSinceEpoch % 350);
      final delay = Duration(milliseconds: baseDelayMs + jitterMs);
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(remaining < delay ? remaining : delay);
    }
    return false;
  }

  /// Clear all local E2EE data (on logout / delete account).
  /// Удаляем ключевую пару и все ключи чатов, чтобы другой пользователь на устройстве не получил старые ключи.
  static Future<void> clearAll() async {
    await _secure.delete(key: _privateKeyKey);
    await _secure.delete(key: _publicKeyKey);
    try {
      final all = await _secure.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_chatKeyPrefix)) {
          await _secure.delete(key: key);
        }
      }
    } catch (_) {}
  }

  // ─── Key backup (password-based) ───

  /// Encrypt private key with password via PBKDF2 + AES-GCM and upload to server.
  static Future<void> _uploadKeyBackup(String privB64, String pubB64, String password) async {
    try {
      final salt = _aesGcm.newNonce(); // 12 bytes of random salt
      final derivedKey = await _pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

      final nonce = _aesGcm.newNonce();
      final encrypted = await _aesGcm.encrypt(
        utf8.encode(privB64),
        secretKey: derivedKey,
        nonce: nonce,
      );

      final encB64 = base64Encode(encrypted.cipherText + encrypted.mac.bytes);
      final saltB64 = base64Encode(salt);
      final nonceB64 = base64Encode(nonce);

      final token = await StorageService.getToken();
      if (token == null) return;
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/e2ee/key-backup'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'encryptedPrivateKey': encB64,
          'salt': saltB64,
          'nonce': nonceB64,
          'publicKey': pubB64,
        }),
      );
    } catch (_) {}
  }

  /// Try to restore key pair from server backup using password.
  /// Returns true if restored successfully.
  static Future<bool> _tryRestoreFromBackup(String password) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return false;
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/e2ee/key-backup'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) return false;

      final data = jsonDecode(resp.body);
      final encB64 = data['encryptedPrivateKey'] as String?;
      final saltB64 = data['salt'] as String?;
      final nonceB64 = data['nonce'] as String?;
      final pubB64 = data['publicKey'] as String?;
      if (encB64 == null || saltB64 == null || nonceB64 == null || pubB64 == null) return false;

      final salt = base64Decode(saltB64);
      final derivedKey = await _pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

      final encBytes = base64Decode(encB64);
      final nonce = base64Decode(nonceB64);
      const macLen = 16;
      final cipherText = encBytes.sublist(0, encBytes.length - macLen);
      final mac = Mac(encBytes.sublist(encBytes.length - macLen));

      final decrypted = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: derivedKey,
      );

      final privB64 = utf8.decode(decrypted);

      await _secure.write(key: _privateKeyKey, value: privB64);
      await _secure.write(key: _publicKeyKey, value: pubB64);

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Manually trigger backup (e.g. from settings screen).
  static Future<bool> backupKeysWithPassword(String password) async {
    try {
      final privB64 = await _secure.read(key: _privateKeyKey);
      final pubB64 = await _secure.read(key: _publicKeyKey);
      if (privB64 == null || pubB64 == null) return false;
      await _uploadKeyBackup(privB64, pubB64, password);
      return true;
    } catch (_) {
      return false;
    }
  }
}
