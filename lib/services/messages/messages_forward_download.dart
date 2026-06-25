import 'dart:typed_data';

import '../../utils/timed_http.dart';
import '../chat_key_service.dart';

const int forwardDownloadMaxBytes = 40 * 1024 * 1024;

Future<Uint8List> downloadUrlBytesForForward(String url) async {
  final r = await timedGet(Uri.parse(url), timeout: const Duration(seconds: 120));
  if (r.statusCode != 200) {
    throw Exception('Не удалось скачать файл для пересылки: HTTP ${r.statusCode}');
  }
  if (r.bodyBytes.length > forwardDownloadMaxBytes) {
    throw Exception('Вложение слишком большое для пересылки');
  }
  return Uint8List.fromList(r.bodyBytes);
}

/// Если байты зашифрованы ключом исходного чата — расшифровываем; иначе возвращаем как есть.
Future<Uint8List> unwrapForwardImageBytes(String sourceChatId, Uint8List bytes) async {
  if (!ChatKeyService.looksLikeEncryptedBytes(bytes)) {
    return bytes;
  }
  final d = await ChatKeyService.decryptBytes(sourceChatId, bytes);
  if (d == null) {
    throw Exception(
      'Не удалось расшифровать изображение для пересылки. Откройте исходный чат и попробуйте снова.',
    );
  }
  return d;
}

String forwardImageStubName(String imageUrl) {
  try {
    final segs = Uri.parse(imageUrl).pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty) {
      final seg = segs.last;
      if (seg.contains('.') && seg.length <= 200) return seg;
    }
  } catch (_) {}
  return 'forward.jpg';
}
