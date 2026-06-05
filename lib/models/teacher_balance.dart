class TeacherBalanceSummary {
  final int teacherId;
  final double balance;
  final String? label;

  const TeacherBalanceSummary({
    required this.teacherId,
    required this.balance,
    this.label,
  });

  factory TeacherBalanceSummary.fromJson(Map<String, dynamic> json) {
    return TeacherBalanceSummary(
      teacherId: _parseInt(json['teacher_id'] ?? json['teacherId']) ?? 0,
      balance: _parseDouble(json['balance']),
      label: json['label']?.toString(),
    );
  }
}

class TeacherBalanceTransaction {
  final int id;
  final int teacherId;
  final double amount;
  final String type;
  final String typeLabel;
  final String description;
  final int? reportId;
  final int? lessonId;
  final int? createdBy;
  final String createdByName;
  final DateTime? createdAt;

  const TeacherBalanceTransaction({
    required this.id,
    required this.teacherId,
    required this.amount,
    required this.type,
    required this.typeLabel,
    required this.description,
    this.reportId,
    this.lessonId,
    this.createdBy,
    this.createdByName = '',
    this.createdAt,
  });

  factory TeacherBalanceTransaction.fromJson(Map<String, dynamic> json) {
    DateTime? createdAt;
    final raw = json['created_at'];
    if (raw != null) {
      try {
        createdAt = DateTime.parse(raw.toString()).toLocal();
      } catch (_) {}
    }
    return TeacherBalanceTransaction(
      id: _parseInt(json['id']) ?? 0,
      teacherId: _parseInt(json['teacher_id']) ?? 0,
      amount: _parseDouble(json['amount']),
      type: json['type']?.toString() ?? '',
      typeLabel: json['type_label']?.toString() ?? json['type']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      reportId: _parseInt(json['report_id']),
      lessonId: _parseInt(json['lesson_id']),
      createdBy: _parseInt(json['created_by']),
      createdByName: json['created_by_name']?.toString() ?? '',
      createdAt: createdAt,
    );
  }

  bool get isCredit => amount > 0;
}

class TeacherBalanceListItem {
  final int teacherId;
  final String label;
  final double balance;

  const TeacherBalanceListItem({
    required this.teacherId,
    required this.label,
    required this.balance,
  });

  factory TeacherBalanceListItem.fromJson(Map<String, dynamic> json) {
    return TeacherBalanceListItem(
      teacherId: _parseInt(json['teacherId'] ?? json['teacher_id']) ?? 0,
      label: json['label']?.toString() ?? '',
      balance: _parseDouble(json['balance']),
    );
  }
}

double _parseDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int? _parseInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
