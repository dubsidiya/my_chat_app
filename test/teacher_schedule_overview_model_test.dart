import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/teacher_schedule_overview.dart';

void main() {
  test('TeacherScheduleOverview.fromJson and cellAt', () {
    final o = TeacherScheduleOverview.fromJson({
      'from': '2026-01-01',
      'to': '2026-01-31',
      'teachers': [
        {'id': 1, 'label': 'Иван'},
        {'id': 2, 'label': 'Мария'},
      ],
      'time_slots': ['18:00'],
      'cells': [
        {
          'weekday': 2,
          'time_slot': '18:00',
          'total_count': 3,
          'is_gap': false,
          'is_overload': true,
          'teachers': [
            {
              'teacher_id': 1,
              'teacher_label': 'Иван',
              'count': 2,
              'load_level': 'high',
              'students': [
                {'student_id': 10, 'student_name': 'Петя', 'lesson_count': 2},
              ],
            },
            {
              'teacher_id': 2,
              'teacher_label': 'Мария',
              'count': 1,
              'load_level': 'normal',
              'students': [
                {'student_id': 11, 'student_name': 'Саша', 'lesson_count': 1},
              ],
            },
          ],
        },
        {
          'weekday': 2,
          'time_slot': '19:00',
          'total_count': 0,
          'is_gap': true,
          'is_overload': false,
          'teachers': [],
        },
      ],
      'max_total_count': 3,
      'active_weekdays': [2],
      'insights': {'overload_cells': 1, 'gap_cells': 1, 'total_lessons': 3},
    });

    expect(o.teachers.length, 2);
    expect(o.insights.overloadCells, 1);
    final cell = o.cellAt(2, '18:00');
    expect(cell?.totalCount, 3);
    expect(cell?.isOverload, isTrue);
    expect(cell?.teachers.first.students.first.studentName, 'Петя');
  });
}
