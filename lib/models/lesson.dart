class Lesson {
  final int id;
  final int studentId;
  final DateTime lessonDate;
  final String? lessonTime;
  final int durationMinutes;
  final double price;
  final String? notes;
  final String status;
  final bool isChargeable;
  final int? originLessonId;
  final DateTime createdAt;

  Lesson({
    required this.id,
    required this.studentId,
    required this.lessonDate,
    this.lessonTime,
    required this.durationMinutes,
    required this.price,
    this.notes,
    this.status = 'attended',
    this.isChargeable = true,
    this.originLessonId,
    required this.createdAt,
  });

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double _parseDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static bool _parseBool(dynamic v, {bool fallback = true}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  factory Lesson.fromJson(Map<String, dynamic> json) {
    final id = _parseInt(json['id']);
    final studentId = _parseInt(json['student_id']);
    if (id == null || studentId == null) {
      throw FormatException('Invalid lesson id or student_id');
    }
    return Lesson(
      id: id,
      studentId: studentId,
      lessonDate: DateTime.parse(json['lesson_date'] as String),
      lessonTime: json['lesson_time'] as String?,
      durationMinutes: _parseInt(json['duration_minutes']) ?? 60,
      price: _parseDouble(json['price']),
      notes: json['notes'] as String?,
      status: (json['status'] ?? 'attended').toString(),
      isChargeable: _parseBool(json['is_chargeable']),
      originLessonId: _parseInt(json['origin_lesson_id']),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

