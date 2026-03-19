import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/e2ee_image.dart';

class PhotoViewerScreen extends StatelessWidget {
  final String imageUrl;
  final String? title;
  final String? chatId;

  const PhotoViewerScreen({
    super.key,
    required this.imageUrl,
    this.title,
    this.chatId,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title ?? '', overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: E2eeImage(
            imageUrl: imageUrl,
            chatId: chatId,
            fit: BoxFit.contain,
            placeholder: (_, __) => const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGlow),
            ),
            errorWidget: (_, __, ___) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_rounded, color: scheme.error, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'Не удалось загрузить изображение',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

