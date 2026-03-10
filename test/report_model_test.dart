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
      expect(report.reportDate.year, 2025);
      expect(report.reportDate.month, 3);
      expect(report.reportDate.day, 1);
      expect(report.content, 'Текст отчёта');
      expect(report.isLate, true);
      expect(report.createdAt.toUtc(), DateTime.utc(2025, 3, 2, 10, 0, 0));
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

    test('isEdited false когда updated_at null или раньше created_at', () {
      expect(
        Report.fromJson({
          'id': 1,
          'report_date': '2025-03-01',
          'content': 'x',
          'is_late': false,
          'created_at': '2025-03-01T10:00:00Z',
        }).isEdited,
        false,
      );
    });

    test('lessons_count и lessons парсятся', () {
      final r = Report.fromJson({
        'id': 1,
        'report_date': '2025-03-01',
        'content': 'x',
        'is_late': false,
        'created_at': '2025-03-01T10:00:00Z',
        'lessons_count': 2,
        'lessons': [
          {'id': 1, 'student_id': 10, 'price': 2000},
          {'id': 2, 'student_id': 11, 'price': 1500},
        ],
      });
      expect(r.lessonsCount, 2);
      expect(r.lessons!.length, 2);
      expect(r.lessons![0]['price'], 2000);
    });
  });
}
