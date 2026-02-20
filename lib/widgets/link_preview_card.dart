import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/link_preview.dart';
import '../theme/app_colors.dart';

class LinkPreviewCard extends StatelessWidget {
  final String url;
  final LinkPreview preview;
  final bool isMine;

  const LinkPreviewCard({
    super.key,
    required this.url,
    required this.preview,
    required this.isMine,
  });

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isMine ? Colors.white.withValues(alpha: 0.12) : AppColors.cardElevatedDark.withValues(alpha: 0.9);
    final border = isMine ? Colors.white.withValues(alpha: 0.18) : scheme.outline.withValues(alpha: 0.22);
    final title = preview.title.trim().isEmpty ? Uri.parse(url).host : preview.title.trim();
    final site = (preview.siteName ?? Uri.parse(url).host).trim();
    final img = (preview.imageUrl ?? '').trim();

    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (img.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: img,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  memCacheWidth: 256,
                  placeholder: (_, __) => Container(
                    width: 84,
                    height: 84,
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 84,
                    height: 84,
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                    child: Icon(Icons.link_rounded, color: scheme.onSurface.withValues(alpha: 0.55)),
                  ),
                ),
              )
            else
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Icon(Icons.link_rounded, color: scheme.onSurface.withValues(alpha: 0.55)),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      site,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isMine ? Colors.white70 : scheme.onSurface.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isMine ? Colors.white : scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isMine ? Colors.white70 : scheme.onSurface.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w500,
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

