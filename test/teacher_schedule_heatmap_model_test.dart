import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/teacher_schedule_heatmap.dart';

void main() {
  test('TeacherScheduleHeatmap.fromJson and countAt', () {
    final h = TeacherScheduleHeatmap.fromJson({
      'teacher_id': 2,
      'teacher_label': 'Иванов',
      'from': '2026-01-01',
      'to': '2026-01-31',
      'time_slots': ['10:00', '11:00'],
      'cells': [
        {'weekday': 1, 'time_slot': '10:00', 'count': 3},
        {'weekday': 3, 'time_slot': '11:00', 'count': 1},
      ],
      'max_count': 3,
      'total_lessons': 4,
      'lessons_without_time': 0,
    });
    expect(h.countAt(1, '10:00'), 3);
    expect(h.countAt(2, '10:00'), 0);
    expect(h.totalLessons, 4);
  });
}
