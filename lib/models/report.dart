class Report {
  final int id;
  final DateTime reportDate;
  final String content;
  final bool isLate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? lessonsCount;
  /// Сколько занятий со статусом «отмена в день проведения» (cancel_same_day).
  final int? cancelSameDayCount;
  /// Сколько занятий со статусом «пропуск» (missed).
  final int? missedCount;
  final List<Map<String, dynamic>>? lessons;
  /// ID пользователя, создавшего отчёт (для списка «все отчёты»).
  final int? createdBy;
  /// Email создателя отчёта (для списка «все отчёты»).
  final String? createdByEmail;
  /// ФИО / display_name создателя (приоритет над email в UI «Кто сдал»).
  final String? createdByDisplayName;

  Report({
    required this.id,
    required this.reportDate,
    required this.content,
    required this.isLate,
    required this.createdAt,
    this.updatedAt,
    this.lessonsCount,
    this.cancelSameDayCount,
    this.missedCount,
    this.lessons,
    this.createdBy,
    this.createdByEmail,
    this.createdByDisplayName,
  });

  /// Подпись «кто сдал»: display_name, иначе email.
  String? get createdByLabel {
    final name = createdByDisplayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = createdByEmail?.trim();
    if (email != null && email.isNotEmpty) return email;
    return null;
  }

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
      cancelSameDayCount: _parseInt(json['cancel_same_day_count']),
      missedCount: _parseInt(json['missed_count']),
      lessons: lessonsParsed,
      createdBy: _parseInt(json['created_by']),
      createdByEmail: json['created_by_email']?.toString(),
      createdByDisplayName: json['created_by_display_name']?.toString(),
    );
  }

  bool get isEdited => updatedAt != null && updatedAt!.isAfter(createdAt);

  /// Есть ли в отчёте отмены в день проведения.
  bool get hasCancelSameDay => (cancelSameDayCount ?? 0) > 0;

  /// Есть ли в отчёте пропуски.
  bool get hasMissed => (missedCount ?? 0) > 0;
}

