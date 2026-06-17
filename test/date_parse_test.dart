import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/utils/date_parse.dart';

void main() {
  group('parseCalendarDate', () {
    test('parses YYYY-MM-DD without day shift', () {
      final d = parseCalendarDate('2025-03-01T00:00:00.000Z');
      expect(d.year, 2025);
      expect(d.month, 3);
      expect(d.day, 1);
    });

    test('parses plain date string', () {
      final d = parseCalendarDate('2025-06-17');
      expect(d.year, 2025);
      expect(d.month, 6);
      expect(d.day, 17);
    });
  });

  group('parseServerInstant', () {
    test('treats ISO without timezone as UTC', () {
      final d = parseServerInstant('2025-03-02T10:00:00');
      expect(d.isUtc, true);
      expect(d.hour, 10);
    });

    test('parses Z suffix as UTC', () {
      final d = parseServerInstant('2025-03-02T10:00:00Z');
      expect(d.isUtc, true);
      expect(d.hour, 10);
    });
  });
}
