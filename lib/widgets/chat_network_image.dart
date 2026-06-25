import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/chat_key_service.dart';
import '../utils/timed_http.dart';

/// Изображение чата по URL. При [chatId] и зашифрованном ответе — расшифровывает
/// его общим ключом чата; иначе показывает как обычную (кэшируемую) картинку.
class ChatNetworkImage extends StatefulWidget {
  final String imageUrl;
  final String? chatId;
  final BoxFit fit;
  final int? memCacheWidth;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;

  const ChatNetworkImage({
    super.key,
    required this.imageUrl,
    this.chatId,
    this.fit = BoxFit.contain,
    this.memCacheWidth,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<ChatNetworkImage> createState() => _ChatNetworkImageState();
}

class _ChatNetworkImageState extends State<ChatNetworkImage> {
  Future<Uint8List?>? _decryptFuture;

  bool get _hasChatId => widget.chatId != null && widget.chatId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _primeFutureIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ChatNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl || oldWidget.chatId != widget.chatId) {
      _primeFutureIfNeeded();
    }
  }

  void _primeFutureIfNeeded() {
    _decryptFuture = _hasChatId ? _fetchAndDecrypt(widget.imageUrl, widget.chatId!) : null;
  }

  Widget _plain() => CachedNetworkImage(
        imageUrl: widget.imageUrl,
        fit: widget.fit,
        memCacheWidth: widget.memCacheWidth,
        httpHeaders: kIsWeb ? {'Access-Control-Allow-Origin': '*'} : null,
        placeholder: widget.placeholder ?? (_, __) => const SizedBox.shrink(),
        errorWidget:
            widget.errorWidget ?? (_, __, ___) => const Icon(Icons.broken_image_rounded),
      );

  @override
  Widget build(BuildContext context) {
    if (!_hasChatId) return _plain();
    return FutureBuilder<Uint8List?>(
      future: _decryptFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.placeholder != null
              ? widget.placeholder!(context, widget.imageUrl)
              : const Center(child: CircularProgressIndicator());
        }
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(bytes, fit: widget.fit, cacheWidth: widget.memCacheWidth);
        }
        // Не зашифровано / не удалось расшифровать — пробуем как обычную картинку.
        return _plain();
      },
    );
  }

  /// Возвращает расшифрованные байты, сырые (если не зашифровано) или null при ошибке.
  static Future<Uint8List?> _fetchAndDecrypt(String url, String chatId) async {
    try {
      final response = await timedGet(Uri.parse(url), timeout: kHttpUploadTimeout);
      if (response.statusCode != 200) return null;
      final bytes = Uint8List.fromList(response.bodyBytes);
      if (bytes.isEmpty) return null;
      if (ChatKeyService.looksLikeEncryptedBytes(bytes)) {
        return ChatKeyService.decryptBytes(chatId, bytes);
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
