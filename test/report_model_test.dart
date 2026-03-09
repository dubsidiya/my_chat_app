import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/report.dart';

void main() {
  group('Report.fromJson', () {
    test('парсит обязательные поля и is_late', () {
      final json = {
        'id': 1,
        'report_date': '2025-03-01',
        'content': 'Текст отчёта',
        'is_late': true,
        'created_at': '2025-03-02T10:00:00Z',
      };
      final report = Report.fromJson(json);
      expect(report.id, 1);
      expect(report.reportDate, DateTime.utc(2025, 3, 1));
      expect(report.content, 'Текст отчёта');
      expect(report.isLate, true);
      expect(report.createdAt, DateTime.utc(2025, 3, 2, 10, 0, 0));
    });

    test('is_late false когда false или отсутствует', () {
      expect(Report.fromJson({
        'id': 2,
        'report_date': '2025-03-01',
        'content': 'x',
        'is_late': false,
        'created_at': '2025-03-01T12:00:00Z',
      }).isLate, false);
      expect(Report.fromJson({
        'id': 3,
        'report_date': '2025-03-01',
        'content': 'x',
        'created_at': '2025-03-01T12:00:00Z',
      }).isLate, false);
    });

    test('isEdited когда updated_at после created_at', () {
      final r = Report.fromJson({
        'id': 1,
        'report_date': '2025-03-01',
        'content': 'x',
        'is_late': false,
        'created_at': '2025-03-01T10:00:00Z',
        'updated_at': '2025-03-01T11:00:00Z',
      });
      expect(r.isEdited, true);
    });
  });
}
