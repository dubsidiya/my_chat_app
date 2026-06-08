import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/teacher_placement_plan.dart';

void main() {
  test('TeacherPlacementPlan.fromJson', () {
    final plan = TeacherPlacementPlan.fromJson({
      'from': '2026-01-01',
      'to': '2026-01-31',
      'hint': 'test',
      'teachers': [
        {
          'teacher_id': 1,
          'teacher_label': 'Иван',
          'typical_weekdays': ['Вт', 'Чт'],
          'open_slots_count': 1,
          'slots': [
            {
              'weekday': 2,
              'weekday_label': 'Вт',
              'time_slot': '18:00',
              'lessons_count': 4,
              'students_count': 2,
              'weeks_active': 3,
              'is_typical_day': true,
              'is_recurring': true,
              'placement_status': 'open',
              'placement_label': 'Можно поставить',
              'students': [
                {'student_id': 10, 'student_name': 'Петя'},
              ],
            },
          ],
        },
      ],
    });

    expect(plan.teachers.single.openSlotsCount, 1);
    expect(plan.teachers.single.openSlots.single.timeSlot, '18:00');
    expect(plan.teachers.single.slots.single.placementLabel, 'Можно поставить');
  });
}
