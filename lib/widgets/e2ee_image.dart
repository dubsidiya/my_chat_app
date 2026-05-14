import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/e2ee_service.dart';
import '../utils/timed_http.dart';

/// Изображение по URL; при [chatId] и зашифрованном ответе — расшифровывает ключом чата.
class E2eeImage extends StatefulWidget {
  final String imageUrl;
  final String? chatId;
  final BoxFit fit;
  final int? memCacheWidth;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  const E2eeImage({
    super.key,
    required this.imageUrl,
    this.chatId,
    this.fit = BoxFit.contain,
    this.memCacheWidth,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<E2eeImage> createState() => _E2eeImageState();
}

class _E2eeImageState extends State<E2eeImage> {
  Future<Uint8List?>? _decryptFuture;

  bool get _hasChatId => widget.chatId != null && widget.chatId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _primeFutureIfNeeded();
  }

  @override
  void didUpdateWidget(covariant E2eeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.imageUrl != widget.imageUrl || oldWidget.chatId != widget.chatId;
    if (!sourceChanged) return;
    _primeFutureIfNeeded();
  }

  void _primeFutureIfNeeded() {
    if (!_hasChatId) {
      _decryptFuture = null;
      return;
    }
    _decryptFuture = _fetchAndDecrypt(widget.imageUrl, widget.chatId!);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasChatId) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl,
        fit: widget.fit,
        memCacheWidth: widget.memCacheWidth,
        httpHeaders: kIsWeb ? {'Access-Control-Allow-Origin': '*'} : null,
        placeholder: widget.placeholder ?? (_, __) => const SizedBox.shrink(),
        errorWidget:
            widget.errorWidget ??
            (_, __, ___) => const Icon(Icons.broken_image_rounded),
      );
    }
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
          return Image.memory(
            bytes,
            fit: widget.fit,
            cacheWidth: widget.memCacheWidth,
          );
        }
        return CachedNetworkImage(
          imageUrl: widget.imageUrl,
          fit: widget.fit,
          memCacheWidth: widget.memCacheWidth,
          httpHeaders: kIsWeb ? {'Access-Control-Allow-Origin': '*'} : null,
          placeholder: widget.placeholder ?? (_, __) => const SizedBox.shrink(),
          errorWidget:
              widget.errorWidget ??
              (_, __, ___) => const Icon(Icons.broken_image_rounded),
        );
      },
    );
  }

  /// Возвращает расшифрованные байты изображения или сырые, если не E2EE. null при ошибке.
  static Future<Uint8List?> _fetchAndDecrypt(String url, String chatId) async {
    try {
      final response = await timedGet(Uri.parse(url), timeout: kHttpUploadTimeout);
      if (response.statusCode != 200) return null;
      final bytes = Uint8List.fromList(response.bodyBytes);
      if (bytes.isEmpty) return null;
      if (E2eeService.looksLikeEncryptedBytes(bytes)) {
        return E2eeService.decryptBytes(chatId, bytes);
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
