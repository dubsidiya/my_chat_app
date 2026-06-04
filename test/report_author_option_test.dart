import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/report_author_option.dart';

void main() {
  group('ReportAuthorOption', () {
    test('fromJson uses label', () {
      final o = ReportAuthorOption.fromJson({
        'id': 3,
        'label': 'Иванов И.И.',
        'email': 'a@b.ru',
      });
      expect(o.id, 3);
      expect(o.label, 'Иванов И.И.');
    });

    test('fromJson falls back to email', () {
      final o = ReportAuthorOption.fromJson({
        'id': 4,
        'email': 'teacher@example.com',
      });
      expect(o.label, 'teacher@example.com');
    });
  });
}
