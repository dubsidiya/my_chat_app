import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/e2ee_service.dart';

/// Изображение по URL; при [chatId] и зашифрованном ответе — расшифровывает ключом чата.
class E2eeImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (chatId == null || chatId!.isEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: fit,
        memCacheWidth: memCacheWidth,
        httpHeaders: kIsWeb ? {'Access-Control-Allow-Origin': '*'} : null,
        placeholder: placeholder ?? (_, __) => const SizedBox.shrink(),
        errorWidget: errorWidget ?? (_, __, ___) => const Icon(Icons.broken_image_rounded),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _fetchAndDecrypt(imageUrl, chatId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return placeholder != null
              ? placeholder!(context, imageUrl)
              : const Center(child: CircularProgressIndicator());
        }
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(bytes, fit: fit, cacheWidth: memCacheWidth);
        }
        return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: fit,
          memCacheWidth: memCacheWidth,
          httpHeaders: kIsWeb ? {'Access-Control-Allow-Origin': '*'} : null,
          placeholder: placeholder ?? (_, __) => const SizedBox.shrink(),
          errorWidget: errorWidget ?? (_, __, ___) => const Icon(Icons.broken_image_rounded),
        );
      },
    );
  }

  /// Возвращает расшифрованные байты изображения или сырые, если не E2EE. null при ошибке.
  static Future<Uint8List?> _fetchAndDecrypt(String url, String chatId) async {
    try {
      final response = await http.get(Uri.parse(url));
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
