import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'storage_service.dart';

/// End-to-end encryption service.
/// Uses X25519 for key agreement + AES-256-GCM for message encryption.
/// Private keys never leave the device.
class E2eeService {
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static const String _privateKeyKey = 'e2ee_private_key';
  static const String _publicKeyKey = 'e2ee_public_key';
  static const String _chatKeyPrefix = 'e2ee_chat_key_';

  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Generate and persist X25519 key pair on device. Upload public key to server.
  /// Call once after registration/login if no key pair exists.
  static Future<void> ensureKeyPair() async {
    final existing = await _secure.read(key: _privateKeyKey);
    if (existing != null && existing.isNotEmpty) return;

    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    await _secure.write(key: _privateKeyKey, value: base64Encode(privateBytes));
    await _secure.write(key: _publicKeyKey, value: base64Encode(publicKey.bytes));

    await _uploadPublicKey(base64Encode(publicKey.bytes));
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
}
