class Report {
  final int id;
  final DateTime reportDate;
  final String content;
  final bool isLate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? lessonsCount;
  final List<Map<String, dynamic>>? lessons;
  /// ID пользователя, создавшего отчёт (для списка «все отчёты»).
  final int? createdBy;
  /// Email создателя отчёта (для списка «все отчёты»).
  final String? createdByEmail;

  Report({
    required this.id,
    required this.reportDate,
    required this.content,
    required this.isLate,
    required this.createdAt,
    this.updatedAt,
    this.lessonsCount,
    this.lessons,
    this.createdBy,
    this.createdByEmail,
  });

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  factory Report.fromJson(Map<String, dynamic> json) {
    final reportId = _parseInt(json['id']);
    if (reportId == null) {
      throw const FormatException('Invalid report id');
    }

    final lessonsRaw = json['lessons'];
    final lessonsParsed = lessonsRaw is List
        ? lessonsRaw
            .whereType<Map>()
            .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
            .toList()
        : null;

    return Report(
      id: reportId,
      reportDate: DateTime.parse(json['report_date'] as String),
      content: json['content'] as String,
      isLate: json['is_late'] == true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      lessonsCount: json['lessons_count'] != null
          ? _parseInt(json['lessons_count'])
          : null,
      lessons: lessonsParsed,
      createdBy: _parseInt(json['created_by']),
      createdByEmail: json['created_by_email']?.toString(),
    );
  }

  bool get isEdited => updatedAt != null && updatedAt!.isAfter(createdAt);
}

