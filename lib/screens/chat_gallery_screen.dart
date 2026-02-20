import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_media_item.dart';
import '../services/messages_service.dart';
import '../theme/app_colors.dart';
import 'photo_viewer_screen.dart';

class ChatGalleryScreen extends StatefulWidget {
  final String chatId;
  final String chatName;

  const ChatGalleryScreen({
    super.key,
    required this.chatId,
    required this.chatName,
  });

  @override
  State<ChatGalleryScreen> createState() => _ChatGalleryScreenState();
}

class _ChatGalleryScreenState extends State<ChatGalleryScreen> {
  final MessagesService _messagesService = MessagesService();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMediaItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _beforeMessageId;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 800) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _beforeMessageId = null;
      _hasMore = true;
    });
    try {
      final page = await _messagesService.fetchChatMedia(widget.chatId, limit: 60);
      if (!mounted) return;
      setState(() {
        _items.addAll(_dedupe(page));
        _beforeMessageId = _items.isNotEmpty ? _items.last.id : null;
        _hasMore = page.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_beforeMessageId == null || _beforeMessageId!.trim().isEmpty) return;
    setState(() {
      _loadingMore = true;
    });
    try {
      final page = await _messagesService.fetchChatMedia(
        widget.chatId,
        beforeMessageId: _beforeMessageId,
        limit: 60,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(_dedupe(page));
        _beforeMessageId = _items.isNotEmpty ? _items.last.id : _beforeMessageId;
        _hasMore = page.isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasMore = false;
        _loadingMore = false;
      });
    }
  }

  List<ChatMediaItem> _dedupe(List<ChatMediaItem> incoming) {
    if (_items.isEmpty) return incoming;
    final existing = _items.map((e) => e.id).toSet();
    return incoming.where((e) => !existing.contains(e.id)).toList();
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openImage(ChatMediaItem item) {
    final url = item.bestImageUrl;
    if (url == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          imageUrl: url,
          title: widget.chatName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Медиа'),
        backgroundColor: scheme.surface,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGlow),
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, color: scheme.error, size: 38),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.85)),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadInitial,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadInitial,
                  color: AppColors.primary,
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      if (_items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              'Пока нет медиа',
                              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.all(8),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final item = _items[index];
                                if (item.isImage) {
                                  final thumb = (item.imageUrl ?? item.bestImageUrl) ?? '';
                                  return GestureDetector(
                                    onTap: () => _openImage(item),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: CachedNetworkImage(
                                        imageUrl: thumb,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(
                                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                          child: const Icon(Icons.broken_image_rounded),
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                // video tile
                                final url = (item.fileUrl ?? '').trim();
                                return GestureDetector(
                                  onTap: url.isEmpty ? null : () => _openVideo(url),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: scheme.outline.withValues(alpha: 0.25)),
                                    ),
                                    child: Stack(
                                      children: [
                                        Center(
                                          child: Icon(
                                            Icons.play_circle_fill_rounded,
                                            size: 44,
                                            color: scheme.onSurface.withValues(alpha: 0.65),
                                          ),
                                        ),
                                        Positioned(
                                          left: 8,
                                          right: 8,
                                          bottom: 8,
                                          child: Text(
                                            (item.fileName ?? 'Видео').toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: scheme.onSurface.withValues(alpha: 0.75),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              childCount: _items.length,
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: _loadingMore
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryGlow),
                                  ),
                                ),
                              )
                            : const SizedBox(height: 24),
                      ),
                    ],
                  ),
                ),
    );
  }
}

