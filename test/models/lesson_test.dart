import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/lesson.dart';

void main() {
  group('Lesson.fromJson', () {
    test('обязательные поля', () {
      final l = Lesson.fromJson({
        'id': 1,
        'student_id': 10,
        'lesson_date': '2025-03-01',
        'duration_minutes': 60,
        'price': 2000.0,
        'created_at': '2025-03-01T14:00:00Z',
      });
      expect(l.id, 1);
      expect(l.studentId, 10);
      expect(l.durationMinutes, 60);
      expect(l.price, 2000.0);
      expect(l.lessonTime, isNull);
      expect(l.notes, isNull);
    });

    test('lesson_time и notes', () {
      final l = Lesson.fromJson({
        'id': 2,
        'student_id': 10,
        'lesson_date': '2025-03-02',
        'lesson_time': '15:00',
        'duration_minutes': 90,
        'price': 3000,
        'notes': 'Повторение',
        'created_at': '2025-03-02T15:00:00Z',
      });
      expect(l.lessonTime, '15:00');
      expect(l.notes, 'Повторение');
      expect(l.durationMinutes, 90);
    });

    test('linked_report_id и linked_report_date', () {
      final l = Lesson.fromJson({
        'id': 3,
        'student_id': 10,
        'lesson_date': '2025-03-10',
        'duration_minutes': 60,
        'price': 1000,
        'created_at': '2025-03-10T12:00:00Z',
        'linked_report_id': 42,
        'linked_report_date': '2025-03-10',
      });
      expect(l.linkedReportId, 42);
      expect(l.linkedReportDate, DateTime(2025, 3, 10));
      expect(l.isFromDailyReport, isTrue);
    });
  });
}
