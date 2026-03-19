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

  /// Check if local key pair exists.
  static Future<bool> hasLocalKeyPair() async {
    final existing = await _secure.read(key: _privateKeyKey);
    return existing != null && existing.isNotEmpty;
  }

  /// Generate key pair, persist locally, upload public key + encrypted backup to server.
  /// [password] is the user's login password — used to encrypt the private key for backup.
  static Future<void> ensureKeyPair({String? password}) async {
    final existing = await _secure.read(key: _privateKeyKey);
    if (existing != null && existing.isNotEmpty) return;

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
  static Future<void> createChatKey(String chatId, List<Map<String, dynamic>> members) async {
    final chatKey = await _aesGcm.newSecretKey();
    final chatKeyBytes = await chatKey.extractBytes();

    await _secure.write(key: '$_chatKeyPrefix$chatId', value: base64Encode(chatKeyBytes));

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

    await _storeChatKeysOnServer(chatId, keysPayload);
  }

  /// Retrieve and decrypt the chat key from the server.
  static Future<SecretKey?> getChatKey(String chatId) async {
    final cached = await _secure.read(key: '$_chatKeyPrefix$chatId');
    if (cached != null && cached.isNotEmpty) {
      return SecretKey(base64Decode(cached));
    }

    final token = await StorageService.getToken();
    if (token == null) return null;
    try {
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/e2ee/chat-key/$chatId'),
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

      await _secure.write(key: '$_chatKeyPrefix$chatId', value: base64Encode(decrypted));
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

  static Future<String> decryptMessage(String chatId, String encryptedJson) async {
    try {
      final data = jsonDecode(encryptedJson);
      if (data is! Map || data['v'] != '1') return encryptedJson;
      final ct = base64Decode(data['ct'] as String);
      final nonce = base64Decode(data['n'] as String);
      final key = await getChatKey(chatId);
      if (key == null) return '[зашифровано]';

      const macLen = 16;
      final cipherText = ct.sublist(0, ct.length - macLen);
      final mac = Mac(ct.sublist(ct.length - macLen));

      final decrypted = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
      );
      return utf8.decode(decrypted);
    } catch (_) {
      return encryptedJson;
    }
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

  static Future<void> _uploadPublicKey(String publicKeyB64) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/e2ee/public-key'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'publicKey': publicKeyB64}),
    );
  }

  static Future<void> _storeChatKeysOnServer(String chatId, List<Map<String, String>> keys) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/e2ee/chat-keys'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'chatId': chatId, 'keys': keys}),
    );
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
      final keys = data['keys'] as Map<String, dynamic>?;
      if (keys == null) return {};
      return keys.map((k, v) => MapEntry(k, v?.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Clear all local E2EE data (on logout).
  static Future<void> clearAll() async {
    await _secure.delete(key: _privateKeyKey);
    await _secure.delete(key: _publicKeyKey);
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
