import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/link_preview.dart';

class LinkPreviewService {
  static final LinkPreviewService instance = LinkPreviewService._();
  LinkPreviewService._();

  static const String _boxName = 'link_previews';
  static const Duration _ttl = Duration(days: 14);

  Box? _box;
  final Map<String, LinkPreview?> _memory = {};
  final Map<String, Future<LinkPreview?>> _inflight = {};

  Future<void> _ensureBox() async {
    if (_box != null) return;
    _box = await Hive.openBox(_boxName);
  }

  static String? extractFirstUrl(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final re = RegExp(r'(https?:\/\/[^\s<>()]+|www\.[^\s<>()]+)', caseSensitive: false);
    final m = re.firstMatch(t);
    if (m == null) return null;
    var url = m.group(0) ?? '';
    url = url.trim();
    if (url.isEmpty) return null;
    if (url.toLowerCase().startsWith('www.')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.trim().isEmpty) return null;
    return uri.toString();
  }

  Future<LinkPreview?> get(String url) {
    final key = _normalize(url);
    if (key == null) return Future.value(null);
    if (_memory.containsKey(key)) return Future.value(_memory[key]);
    final existing = _inflight[key];
    if (existing != null) return existing;
    final fut = _getImpl(key);
    _inflight[key] = fut;
    fut.whenComplete(() => _inflight.remove(key));
    return fut;
  }

  String? _normalize(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // drop fragment for caching
    return uri.replace(fragment: '').toString();
  }

  bool _isBlockedHost(String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return true;
    if (h == 'localhost' || h.endsWith('.localhost')) return true;
    if (h.endsWith('.local') || h.endsWith('.internal')) return true;
    if (h == '0.0.0.0') return true;
    if (h == '127.0.0.1' || h.startsWith('127.')) return true;
    if (h.startsWith('10.')) return true;
    if (h.startsWith('192.168.')) return true;
    if (h.startsWith('172.')) {
      final parts = h.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? -1;
        if (second >= 16 && second <= 31) return true;
      }
    }
    // simple IPv6 loopback/local checks
    if (h == '::1' || h.startsWith('fe80:') || h.startsWith('fc') || h.startsWith('fd')) return true;
    return false;
  }

  Future<LinkPreview?> _getImpl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (_isBlockedHost(uri.host)) {
        _memory[url] = null;
        return null;
      }

      await _ensureBox();

      // hive cache
      final cached = _box?.get(url);
      if (cached is Map) {
        final m = cached.map((k, v) => MapEntry(k.toString(), v));
        final preview = LinkPreview.fromJson(m);
        final ts = DateTime.tryParse(preview.fetchedAtIso);
        if (ts != null && DateTime.now().difference(ts) <= _ttl) {
          _memory[url] = preview;
          return preview;
        }
      }

      // On web, CORS will often block HTML fetch. We'll try best-effort anyway.
      final resp = await http
          .get(
            uri,
            headers: const {
              'Accept': 'text/html,application/xhtml+xml',
              'User-Agent': 'my_chat_app/1.0',
            },
          )
          .timeout(const Duration(seconds: 5));

      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      if (!ct.contains('text/html') && !ct.contains('application/xhtml+xml')) {
        _memory[url] = null;
        return null;
      }

      final body = _decodeBody(resp);
      final meta = _parseOg(body);

      final title = (meta['title'] ?? '').trim();
      final image = (meta['image'] ?? '').trim();
      final siteName = (meta['siteName'] ?? '').trim();

      if (title.isEmpty && image.isEmpty) {
        _memory[url] = null;
        return null;
      }

      final preview = LinkPreview(
        url: url,
        title: title.isNotEmpty ? title : uri.host,
        imageUrl: image.isNotEmpty ? _makeAbsolute(uri, image) : null,
        siteName: siteName.isNotEmpty ? siteName : uri.host,
        fetchedAtIso: DateTime.now().toIso8601String(),
      );

      _memory[url] = preview;
      await _box?.put(url, preview.toJson());
      return preview;
    } catch (_) {
      // For Web: frequent CORS failures — do not treat as error
      if (kIsWeb) {
        _memory[url] = null;
        return null;
      }
      _memory[url] = null;
      return null;
    }
  }

  String _decodeBody(http.Response resp) {
    try {
      return utf8.decode(resp.bodyBytes);
    } catch (_) {
      return resp.body;
    }
  }

  String? _makeAbsolute(Uri base, String imageUrl) {
    final u = imageUrl.trim();
    final parsed = Uri.tryParse(u);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed.toString();
    return base.resolveUri(parsed).toString();
  }

  Map<String, String> _parseOg(String html) {
    final h = html;
    String? pick(RegExp re) {
      final m = re.firstMatch(h);
      if (m == null) return null;
      return _decodeHtmlEntities((m.groupCount >= 1 ? (m.group(1) ?? '') : '').trim());
    }

    final ogTitle = pick(RegExp('<meta[^>]+property=["\\\']og:title["\\\'][^>]+content=["\\\']([^"\\\']+)["\\\']', caseSensitive: false));
    final ogImage = pick(RegExp('<meta[^>]+property=["\\\']og:image["\\\'][^>]+content=["\\\']([^"\\\']+)["\\\']', caseSensitive: false));
    final ogSiteName = pick(RegExp('<meta[^>]+property=["\\\']og:site_name["\\\'][^>]+content=["\\\']([^"\\\']+)["\\\']', caseSensitive: false));
    final titleTag = pick(RegExp(r'<title[^>]*>([^<]{1,300})</title>', caseSensitive: false));

    return {
      'title': ogTitle ?? titleTag ?? '',
      'image': ogImage ?? '',
      'siteName': ogSiteName ?? '',
    };
  }

  String _decodeHtmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
}

