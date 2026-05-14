import 'package:flutter/material.dart';

import 'e2ee_image.dart';

/// Полноэкранный просмотр фото в стиле Telegram/WhatsApp: тёмный фон, зум, тап — закрыть.
class ChatViewerImageItem {
  final String imageUrl;
  final String originalImageUrl;
  final String fileName;

  const ChatViewerImageItem({
    required this.imageUrl,
    required this.originalImageUrl,
    required this.fileName,
  });
}

class ChatFullscreenImageViewer extends StatefulWidget {
  final List<ChatViewerImageItem> images;
  final int initialIndex;
  final String? chatId;
  final void Function(ChatViewerImageItem item)? onDownload;

  const ChatFullscreenImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.chatId,
    this.onDownload,
  });

  @override
  State<ChatFullscreenImageViewer> createState() =>
      _ChatFullscreenImageViewerState();
}

class _ChatFullscreenImageViewerState extends State<ChatFullscreenImageViewer> {
  static const double _dismissThreshold = 120;
  static const double _maxDragForOpacity = 320;
  static const double _maxDragForImageOpacity = 220;

  late final PageController _pageController;
  late final List<TransformationController> _zoomControllers;
  late int _currentIndex;
  bool _isZoomed = false;
  bool _showChrome = true;
  double _verticalDragOffset = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.images.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _zoomControllers = List<TransformationController>.generate(
      widget.images.length,
      (_) => TransformationController(),
    );
    for (final controller in _zoomControllers) {
      controller.addListener(_updateZoomState);
    }
  }

  @override
  void dispose() {
    for (final controller in _zoomControllers) {
      controller
        ..removeListener(_updateZoomState)
        ..dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  bool _isIdentity(Matrix4 matrix) {
    const eps = 0.001;
    return (matrix.storage[0] - 1).abs() < eps &&
        (matrix.storage[5] - 1).abs() < eps &&
        (matrix.storage[10] - 1).abs() < eps &&
        matrix.storage[12].abs() < eps &&
        matrix.storage[13].abs() < eps;
  }

  void _updateZoomState() {
    if (!mounted || _zoomControllers.isEmpty) return;
    final zoomed = !_isIdentity(_zoomControllers[_currentIndex].value);
    if (zoomed == _isZoomed) return;
    setState(() {
      _isZoomed = zoomed;
    });
  }

  void _resetCurrentZoom() {
    if (_zoomControllers.isEmpty) return;
    _zoomControllers[_currentIndex].value = Matrix4.identity();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    setState(() {
      _verticalDragOffset += details.delta.dy;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    if (_verticalDragOffset.abs() >= _dismissThreshold) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _verticalDragOffset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    final currentItem = widget.images[_currentIndex];
    final backgroundOpacity =
        (1 - (_verticalDragOffset.abs() / _maxDragForOpacity)).clamp(0.45, 1.0);
    final imageOpacity =
        (1 - (_verticalDragOffset.abs() / _maxDragForImageOpacity)).clamp(
          0.2,
          1.0,
        );

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: backgroundOpacity),
      body: GestureDetector(
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: imageOpacity,
              child: Transform.translate(
                offset: Offset(0, _verticalDragOffset),
                child: PageView.builder(
                  controller: _pageController,
                  physics: _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  onPageChanged: (index) {
                    if (_currentIndex == index) return;
                    _resetCurrentZoom();
                    setState(() {
                      _currentIndex = index;
                      _verticalDragOffset = 0;
                    });
                    _updateZoomState();
                  },
                  itemCount: widget.images.length,
                  itemBuilder: (context, index) {
                    final item = widget.images[index];
                    return GestureDetector(
                      onTap: () => setState(() => _showChrome = !_showChrome),
                      child: Center(
                        child: InteractiveViewer(
                          transformationController: _zoomControllers[index],
                          minScale: 1.0,
                          maxScale: 5.0,
                          panEnabled: true,
                          clipBehavior: Clip.none,
                          child: E2eeImage(
                            imageUrl: item.imageUrl,
                            chatId: widget.chatId,
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
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: Colors.white54,
                                    size: 56,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Не удалось загрузить изображение',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_showChrome)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Column(
                    children: [
                      Row(
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
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              if (widget.images.length > 1)
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    '${_currentIndex + 1}/${widget.images.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (widget.onDownload != null)
                                Material(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(24),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(24),
                                    onTap: () => widget.onDownload?.call(currentItem),
                                    child: const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Icon(
                                        Icons.download_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (!_isZoomed)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Свайп вниз, чтобы закрыть',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                    ],
                    ),
                  ),
                    ),
          ],
        ),
      ),
    );
  }
}
