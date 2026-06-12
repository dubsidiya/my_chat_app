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

  group('filterReportTeachers', () {
    final teachers = [
      const ReportAuthorOption(id: 1, label: 'Иванов Иван'),
      const ReportAuthorOption(id: 2, label: 'Петрова Мария'),
      const ReportAuthorOption(id: 3, label: 'Сидоров Алексей'),
    ];

    test('empty query returns all teachers plus "all" option', () {
      final picks = filterReportTeachers(teachers, '');
      expect(picks.map((p) => p.label).toList(), [
        'Все преподаватели',
        'Иванов Иван',
        'Петрова Мария',
        'Сидоров Алексей',
      ]);
    });

    test('filters by partial name case-insensitively', () {
      final picks = filterReportTeachers(teachers, 'мар');
      expect(picks.map((p) => p.label).toList(), ['Петрова Мария']);
    });

    test('matches "Все преподаватели" option', () {
      final picks = filterReportTeachers(teachers, 'все');
      expect(picks, [ReportTeacherFilterOption.all]);
    });

    test('returns empty list when nothing matches', () {
      expect(filterReportTeachers(teachers, 'zzz'), isEmpty);
    });

    test('empty teacher list still offers "all" option', () {
      expect(filterReportTeachers([], ''), [ReportTeacherFilterOption.all]);
    });

    test('trims query whitespace', () {
      final picks = filterReportTeachers(teachers, '  мар  ');
      expect(picks.map((p) => p.label).toList(), ['Петрова Мария']);
    });
  });
}
