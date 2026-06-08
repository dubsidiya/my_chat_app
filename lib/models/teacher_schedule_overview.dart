class TeacherScheduleOverview {
  final String from;
  final String to;
  final List<TeacherScheduleOverviewTeacher> teachers;
  final List<String> timeSlots;
  final List<TeacherScheduleOverviewCell> cells;
  final int maxTotalCount;
  final List<int> activeWeekdays;
  final TeacherScheduleOverviewInsights insights;

  const TeacherScheduleOverview({
    required this.from,
    required this.to,
    required this.teachers,
    required this.timeSlots,
    required this.cells,
    required this.maxTotalCount,
    required this.activeWeekdays,
    required this.insights,
  });

  factory TeacherScheduleOverview.fromJson(Map<String, dynamic> json) {
    final teachersRaw = json['teachers'];
    final teachers = teachersRaw is List
        ? teachersRaw
            .whereType<Map>()
            .map(
              (m) => TeacherScheduleOverviewTeacher.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : <TeacherScheduleOverviewTeacher>[];

    final slotsRaw = json['time_slots'];
    final timeSlots = slotsRaw is List
        ? slotsRaw.map((e) => e.toString()).toList()
        : <String>[];

    final cellsRaw = json['cells'];
    final cells = cellsRaw is List
        ? cellsRaw
            .whereType<Map>()
            .map(
              (m) => TeacherScheduleOverviewCell.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : <TeacherScheduleOverviewCell>[];

    final weekdaysRaw = json['active_weekdays'];
    final activeWeekdays = weekdaysRaw is List
        ? weekdaysRaw.map((e) => _parseInt(e) ?? 0).where((d) => d >= 1 && d <= 7).toList()
        : <int>[];

    final insightsRaw = json['insights'];
    final insights = insightsRaw is Map
        ? TeacherScheduleOverviewInsights.fromJson(
            insightsRaw.map((k, v) => MapEntry(k.toString(), v)),
          )
        : const TeacherScheduleOverviewInsights();

    return TeacherScheduleOverview(
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      teachers: teachers,
      timeSlots: timeSlots,
      cells: cells,
      maxTotalCount: _parseInt(json['max_total_count']) ?? 0,
      activeWeekdays: activeWeekdays,
      insights: insights,
    );
  }

  TeacherScheduleOverviewCell? cellAt(int weekday, String timeSlot) {
    for (final c in cells) {
      if (c.weekday == weekday && c.timeSlot == timeSlot) return c;
    }
    return null;
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

class TeacherScheduleOverviewTeacher {
  final int id;
  final String label;

  const TeacherScheduleOverviewTeacher({required this.id, required this.label});

  factory TeacherScheduleOverviewTeacher.fromJson(Map<String, dynamic> json) {
    return TeacherScheduleOverviewTeacher(
      id: TeacherScheduleOverview._parseInt(json['id']) ?? 0,
      label: json['label']?.toString() ?? '',
    );
  }
}

class TeacherScheduleOverviewInsights {
  final int overloadCells;
  final int gapCells;
  final int totalLessons;

  const TeacherScheduleOverviewInsights({
    this.overloadCells = 0,
    this.gapCells = 0,
    this.totalLessons = 0,
  });

  factory TeacherScheduleOverviewInsights.fromJson(Map<String, dynamic> json) {
    return TeacherScheduleOverviewInsights(
      overloadCells: TeacherScheduleOverview._parseInt(json['overload_cells']) ?? 0,
      gapCells: TeacherScheduleOverview._parseInt(json['gap_cells']) ?? 0,
      totalLessons: TeacherScheduleOverview._parseInt(json['total_lessons']) ?? 0,
    );
  }
}

class TeacherScheduleOverviewCell {
  final int weekday;
  final String timeSlot;
  final int totalCount;
  final bool isGap;
  final bool isOverload;
  final List<TeacherScheduleOverviewCellTeacher> teachers;

  const TeacherScheduleOverviewCell({
    required this.weekday,
    required this.timeSlot,
    required this.totalCount,
    required this.isGap,
    required this.isOverload,
    required this.teachers,
  });

  factory TeacherScheduleOverviewCell.fromJson(Map<String, dynamic> json) {
    final teachersRaw = json['teachers'];
    final teachers = teachersRaw is List
        ? teachersRaw
            .whereType<Map>()
            .map(
              (m) => TeacherScheduleOverviewCellTeacher.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : <TeacherScheduleOverviewCellTeacher>[];

    return TeacherScheduleOverviewCell(
      weekday: TeacherScheduleOverview._parseInt(json['weekday']) ?? 0,
      timeSlot: json['time_slot']?.toString() ?? '',
      totalCount: TeacherScheduleOverview._parseInt(json['total_count']) ?? 0,
      isGap: json['is_gap'] == true,
      isOverload: json['is_overload'] == true,
      teachers: teachers,
    );
  }
}

class TeacherScheduleOverviewCellTeacher {
  final int teacherId;
  final String teacherLabel;
  final int count;
  final String loadLevel;
  final List<TeacherScheduleOverviewStudent> students;

  const TeacherScheduleOverviewCellTeacher({
    required this.teacherId,
    required this.teacherLabel,
    required this.count,
    required this.loadLevel,
    required this.students,
  });

  factory TeacherScheduleOverviewCellTeacher.fromJson(Map<String, dynamic> json) {
    final studentsRaw = json['students'];
    final students = studentsRaw is List
        ? studentsRaw
            .whereType<Map>()
            .map(
              (m) => TeacherScheduleOverviewStudent.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : <TeacherScheduleOverviewStudent>[];

    return TeacherScheduleOverviewCellTeacher(
      teacherId: TeacherScheduleOverview._parseInt(json['teacher_id']) ?? 0,
      teacherLabel: json['teacher_label']?.toString() ?? '',
      count: TeacherScheduleOverview._parseInt(json['count']) ?? 0,
      loadLevel: json['load_level']?.toString() ?? 'empty',
      students: students,
    );
  }
}

class TeacherScheduleOverviewStudent {
  final int studentId;
  final String studentName;
  final int lessonCount;

  const TeacherScheduleOverviewStudent({
    required this.studentId,
    required this.studentName,
    required this.lessonCount,
  });

  factory TeacherScheduleOverviewStudent.fromJson(Map<String, dynamic> json) {
    return TeacherScheduleOverviewStudent(
      studentId: TeacherScheduleOverview._parseInt(json['student_id']) ?? 0,
      studentName: json['student_name']?.toString() ?? '',
      lessonCount: TeacherScheduleOverview._parseInt(json['lesson_count']) ?? 0,
    );
  }
}
