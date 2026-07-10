import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/chat_image_cache.dart';

/// Изображение чата по URL.
///
/// С [chatId] — через [ChatImageCache] (память/диск), без повторной загрузки
/// при скролле. Без [chatId] — обычный [CachedNetworkImage].
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
  Uint8List? _bytes;
  /// true после неудачной загрузки из ChatImageCache — фолбэк на CachedNetworkImage.
  bool _fallbackPlain = false;

  bool get _useChatCache =>
      widget.chatId != null && widget.chatId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _prime();
  }

  @override
  void didUpdateWidget(covariant ChatNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.chatId != widget.chatId) {
      _prime();
    }
  }

  void _prime() {
    _fallbackPlain = false;
    if (!_useChatCache) {
      _bytes = null;
      return;
    }
    // Синхронный RAM-hit — без placeholder при обратном скролле.
    final hit = ChatImageCache.peek(widget.imageUrl);
    if (hit != null) {
      _bytes = hit;
      return;
    }
    _bytes = null;
    final url = widget.imageUrl;
    ChatImageCache.get(url, chatId: widget.chatId).then((bytes) {
      if (!mounted || widget.imageUrl != url) return;
      setState(() {
        if (bytes != null && bytes.isNotEmpty) {
          _bytes = bytes;
        } else {
          _fallbackPlain = true;
        }
      });
    });
  }

  Widget _plain() => CachedNetworkImage(
        imageUrl: widget.imageUrl,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: widget.memCacheWidth,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        httpHeaders: kIsWeb ? {'Access-Control-Allow-Origin': '*'} : null,
        placeholder: widget.placeholder ?? (_, __) => const SizedBox.shrink(),
        errorWidget:
            widget.errorWidget ?? (_, __, ___) => const Icon(Icons.broken_image_rounded),
      );

  Widget _decoded(Uint8List bytes) => Image.memory(
        bytes,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: widget.memCacheWidth,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );

  Widget _placeholder() => widget.placeholder != null
      ? widget.placeholder!(context, widget.imageUrl)
      : const Center(child: CircularProgressIndicator());

  @override
  Widget build(BuildContext context) {
    if (!_useChatCache) return _plain();
    if (_bytes != null && _bytes!.isNotEmpty) return _decoded(_bytes!);
    if (_fallbackPlain) return _plain();
    return _placeholder();
  }
}
