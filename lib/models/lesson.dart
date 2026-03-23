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
      durationMinutes: json['duration_minutes'] as int? ?? 60,
      price: (json['price'] ?? 0.0) is double 
          ? json['price'] as double 
          : double.tryParse(json['price'].toString()) ?? 0.0,
      notes: json['notes'] as String?,
      status: (json['status'] ?? 'attended').toString(),
      isChargeable: json['is_chargeable'] == null ? true : json['is_chargeable'] == true,
      originLessonId: _parseInt(json['origin_lesson_id']),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

