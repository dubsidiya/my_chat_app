class TeacherPlacementPlan {
  final String from;
  final String to;
  final String? hint;
  final List<TeacherPlacementTeacher> teachers;

  const TeacherPlacementPlan({
    required this.from,
    required this.to,
    required this.teachers,
    this.hint,
  });

  factory TeacherPlacementPlan.fromJson(Map<String, dynamic> json) {
    final teachersRaw = json['teachers'];
    final teachers = teachersRaw is List
        ? teachersRaw
            .whereType<Map>()
            .map(
              (m) => TeacherPlacementTeacher.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : <TeacherPlacementTeacher>[];

    return TeacherPlacementPlan(
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      hint: json['hint']?.toString(),
      teachers: teachers,
    );
  }
}

class TeacherPlacementTeacher {
  final int teacherId;
  final String teacherLabel;
  final List<String> typicalWeekdays;
  final int openSlotsCount;
  final List<TeacherPlacementSlot> slots;

  const TeacherPlacementTeacher({
    required this.teacherId,
    required this.teacherLabel,
    required this.typicalWeekdays,
    required this.openSlotsCount,
    required this.slots,
  });

  factory TeacherPlacementTeacher.fromJson(Map<String, dynamic> json) {
    final weekdaysRaw = json['typical_weekdays'];
    final typicalWeekdays = weekdaysRaw is List
        ? weekdaysRaw.map((e) => e.toString()).toList()
        : <String>[];

    final slotsRaw = json['slots'];
    final slots = slotsRaw is List
        ? slotsRaw
            .whereType<Map>()
            .map(
              (m) => TeacherPlacementSlot.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : <TeacherPlacementSlot>[];

    return TeacherPlacementTeacher(
      teacherId: _parseInt(json['teacher_id']) ?? 0,
      teacherLabel: json['teacher_label']?.toString() ?? '',
      typicalWeekdays: typicalWeekdays,
      openSlotsCount: _parseInt(json['open_slots_count']) ?? 0,
      slots: slots,
    );
  }

  List<TeacherPlacementSlot> get openSlots =>
      slots.where((s) => s.placementStatus == 'open').toList();
}

class TeacherPlacementSlot {
  final int weekday;
  final String weekdayLabel;
  final String timeSlot;
  final int lessonsCount;
  final int studentsCount;
  final int weeksActive;
  final bool isTypicalDay;
  final bool isRecurring;
  final String placementStatus;
  final String placementLabel;
  final List<TeacherPlacementStudent> students;

  const TeacherPlacementSlot({
    required this.weekday,
    required this.weekdayLabel,
    required this.timeSlot,
    required this.lessonsCount,
    required this.studentsCount,
    required this.weeksActive,
    required this.isTypicalDay,
    required this.isRecurring,
    required this.placementStatus,
    required this.placementLabel,
    required this.students,
  });

  factory TeacherPlacementSlot.fromJson(Map<String, dynamic> json) {
    final studentsRaw = json['students'];
    final students = studentsRaw is List
        ? studentsRaw
            .whereType<Map>()
            .map(
              (m) => TeacherPlacementStudent.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : <TeacherPlacementStudent>[];

    return TeacherPlacementSlot(
      weekday: _parseInt(json['weekday']) ?? 0,
      weekdayLabel: json['weekday_label']?.toString() ?? '',
      timeSlot: json['time_slot']?.toString() ?? '',
      lessonsCount: _parseInt(json['lessons_count']) ?? 0,
      studentsCount: _parseInt(json['students_count']) ?? 0,
      weeksActive: _parseInt(json['weeks_active']) ?? 0,
      isTypicalDay: json['is_typical_day'] == true,
      isRecurring: json['is_recurring'] == true,
      placementStatus: json['placement_status']?.toString() ?? '',
      placementLabel: json['placement_label']?.toString() ?? '',
      students: students,
    );
  }
}

class TeacherPlacementStudent {
  final int studentId;
  final String studentName;

  const TeacherPlacementStudent({
    required this.studentId,
    required this.studentName,
  });

  factory TeacherPlacementStudent.fromJson(Map<String, dynamic> json) {
    return TeacherPlacementStudent(
      studentId: _parseInt(json['student_id']) ?? 0,
      studentName: json['student_name']?.toString() ?? '',
    );
  }
}

int? _parseInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
