import 'package:flutter/material.dart';

import 'e2ee_image.dart';

/// Полноэкранный просмотр фото в стиле Telegram/WhatsApp: тёмный фон, зум, тап — закрыть.
class ChatFullscreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String? chatId;
  final String? originalImageUrl;
  final String fileName;
  final VoidCallback? onDownload;

  const ChatFullscreenImageViewer({
    super.key,
    required this.imageUrl,
    this.chatId,
    this.originalImageUrl,
    required this.fileName,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: E2eeImage(
                  imageUrl: imageUrl,
                  chatId: chatId,
                  fit: BoxFit.contain,
                  memCacheWidth: 1920,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white70,
                      strokeWidth: 2,
                    ),
                  ),
                  errorWidget: (_, __, ___) => const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, color: Colors.white54, size: 56),
                        SizedBox(height: 16),
                        Text(
                          'Не удалось загрузить изображение',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Material(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.close_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  if (onDownload != null)
                    Material(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: onDownload,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.download_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
