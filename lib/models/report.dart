class Report {
  final int id;
  final DateTime reportDate;
  final String content;
  final bool isLate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? lessonsCount;
  final List<Map<String, dynamic>>? lessons;

  Report({
    required this.id,
    required this.reportDate,
    required this.content,
    required this.isLate,
    required this.createdAt,
    this.updatedAt,
    this.lessonsCount,
    this.lessons,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] as int,
      reportDate: DateTime.parse(json['report_date'] as String),
      content: json['content'] as String,
      isLate: json['is_late'] == true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      lessonsCount: json['lessons_count'] != null
          ? (json['lessons_count'] is int
              ? json['lessons_count'] as int
              : int.tryParse(json['lessons_count'].toString()))
          : null,
      lessons: json['lessons'] != null
          ? (json['lessons'] as List).cast<Map<String, dynamic>>()
          : null,
    );
  }

  bool get isEdited => updatedAt != null && updatedAt!.isAfter(createdAt);
}

