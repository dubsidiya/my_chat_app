class TeacherScheduleHeatmap {
  final int teacherId;
  final String teacherLabel;
  final String from;
  final String to;
  final List<String> timeSlots;
  final List<TeacherScheduleCell> cells;
  final int maxCount;
  final int totalLessons;
  final int lessonsWithoutTime;

  const TeacherScheduleHeatmap({
    required this.teacherId,
    required this.teacherLabel,
    required this.from,
    required this.to,
    required this.timeSlots,
    required this.cells,
    required this.maxCount,
    required this.totalLessons,
    required this.lessonsWithoutTime,
  });

  factory TeacherScheduleHeatmap.fromJson(Map<String, dynamic> json) {
    final teacherIdRaw = json['teacher_id'];
    final teacherId = teacherIdRaw is int
        ? teacherIdRaw
        : int.tryParse(teacherIdRaw?.toString() ?? '') ?? 0;

    final slotsRaw = json['time_slots'];
    final timeSlots = slotsRaw is List
        ? slotsRaw.map((e) => e.toString()).toList()
        : <String>[];

    final cellsRaw = json['cells'];
    final cells = cellsRaw is List
        ? cellsRaw
            .whereType<Map>()
            .map(
              (m) => TeacherScheduleCell.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList()
        : <TeacherScheduleCell>[];

    return TeacherScheduleHeatmap(
      teacherId: teacherId,
      teacherLabel: json['teacher_label']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      timeSlots: timeSlots,
      cells: cells,
      maxCount: _parseInt(json['max_count']) ?? 0,
      totalLessons: _parseInt(json['total_lessons']) ?? 0,
      lessonsWithoutTime: _parseInt(json['lessons_without_time']) ?? 0,
    );
  }

  int countAt(int weekday, String timeSlot) {
    for (final c in cells) {
      if (c.weekday == weekday && c.timeSlot == timeSlot) return c.count;
    }
    return 0;
  }

  /// Только слоты с занятиями в этот день недели (без пустых строк из других дней).
  List<TeacherScheduleCell> slotsForWeekday(int weekday) {
    final list = cells
        .where((c) => c.weekday == weekday && c.count > 0 && c.timeSlot.isNotEmpty)
        .toList()
      ..sort((a, b) => a.timeSlot.compareTo(b.timeSlot));
    return list;
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

class TeacherScheduleCell {
  final int weekday;
  final String timeSlot;
  final int count;

  const TeacherScheduleCell({
    required this.weekday,
    required this.timeSlot,
    required this.count,
  });

  factory TeacherScheduleCell.fromJson(Map<String, dynamic> json) {
    return TeacherScheduleCell(
      weekday: TeacherScheduleHeatmap._parseInt(json['weekday']) ?? 0,
      timeSlot: json['time_slot']?.toString() ?? '',
      count: TeacherScheduleHeatmap._parseInt(json['count']) ?? 0,
    );
  }
}
