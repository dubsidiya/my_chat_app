import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/link_preview.dart';

void main() {
  group('LinkPreview', () {
    test('fromJson и toJson roundtrip', () {
      final json = {
        'url': 'https://example.com/page',
        'title': 'Example',
        'imageUrl': 'https://example.com/og.jpg',
        'siteName': 'Example Site',
        'fetchedAtIso': '2025-03-01T12:00:00Z',
      };
      final p = LinkPreview.fromJson(json);
      expect(p.url, 'https://example.com/page');
      expect(p.title, 'Example');
      expect(p.imageUrl, 'https://example.com/og.jpg');
      expect(p.siteName, 'Example Site');
      expect(p.fetchedAtIso, '2025-03-01T12:00:00Z');

      final out = p.toJson();
      expect(out['url'], p.url);
      expect(out['title'], p.title);
    });

    test('snake_case с бэкенда', () {
      final p = LinkPreview.fromJson({
        'url': 'https://a.ru',
        'title': 'T',
        'image_url': 'https://a.ru/img.jpg',
        'site_name': 'Site',
        'fetched_at': '2025-03-01T12:00:00Z',
      });
      expect(p.imageUrl, 'https://a.ru/img.jpg');
      expect(p.siteName, 'Site');
    });
  });
}
