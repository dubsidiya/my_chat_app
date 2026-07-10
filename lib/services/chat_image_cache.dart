import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'chat_key_service.dart';
import '../utils/timed_http.dart';
import 'chat_image_disk_stub.dart'
    if (dart.library.io) 'chat_image_disk_io.dart' as disk;

/// Локальный кэш превью фото чата (память + диск), как в мессенджерах:
/// долистали обратно — картинка из кэша, без повторной сети/расшифровки.
///
/// На диск кладём уже расшифрованные байты (только на устройстве).
/// При logout очищается вместе с ключами чата.
class ChatImageCache {
  ChatImageCache._();

  static const int _maxMemEntries = 96;

  static final LinkedHashMap<String, Uint8List> _mem =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, Future<Uint8List?>> _inflight =
      <String, Future<Uint8List?>>{};

  /// Синхронный hit в RAM — для мгновенного показа без placeholder.
  static Uint8List? peek(String url) {
    final key = _key(url);
    final hit = _mem.remove(key);
    if (hit == null) return null;
    _mem[key] = hit; // LRU touch
    return hit;
  }

  /// Прогреть кэш локальными байтами (отправка фото / тесты).
  static void warm(String url, Uint8List bytes) {
    if (url.trim().isEmpty || bytes.isEmpty) return;
    final key = _key(url);
    _putMem(key, bytes);
    // ignore: unawaited_futures
    disk.writeChatImageDisk(_fileName(key), bytes);
  }

  /// Память → диск → сеть (+ расшифровка при необходимости).
  static Future<Uint8List?> get(String url, {String? chatId}) {
    final key = _key(url);
    final mem = peek(url);
    if (mem != null) return Future<Uint8List?>.value(mem);

    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _load(url, chatId);
    _inflight[key] = future;
    return future.whenComplete(() => _inflight.remove(key));
  }

  static Future<Uint8List?> _load(String url, String? chatId) async {
    final key = _key(url);

    final fromDisk = await disk.readChatImageDisk(_fileName(key));
    if (fromDisk != null && fromDisk.isNotEmpty) {
      _putMem(key, fromDisk);
      return fromDisk;
    }

    try {
      final response = await timedGet(Uri.parse(url), timeout: kHttpUploadTimeout);
      if (response.statusCode != 200) return null;
      var bytes = Uint8List.fromList(response.bodyBytes);
      if (bytes.isEmpty) return null;

      if (chatId != null &&
          chatId.isNotEmpty &&
          ChatKeyService.looksLikeEncryptedBytes(bytes)) {
        final decrypted = await ChatKeyService.decryptBytes(chatId, bytes);
        if (decrypted == null || decrypted.isEmpty) return null;
        bytes = decrypted;
      }

      _putMem(key, bytes);
      // ignore: unawaited_futures
      disk.writeChatImageDisk(_fileName(key), bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static void _putMem(String key, Uint8List bytes) {
    _mem.remove(key);
    _mem[key] = bytes;
    while (_mem.length > _maxMemEntries) {
      _mem.remove(_mem.keys.first);
    }
  }

  static String _key(String url) => url.trim();

  static String _fileName(String key) {
    final digest = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    if (digest.length <= 80) return digest;
    return '${digest.substring(0, 40)}_${digest.hashCode.toRadixString(16)}';
  }

  /// Logout / удаление аккаунта.
  static Future<void> clearAll() async {
    _mem.clear();
    _inflight.clear();
    await disk.clearChatImageDisk();
  }
}
