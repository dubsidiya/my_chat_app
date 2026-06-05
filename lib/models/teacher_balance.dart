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
  /// Дата занятия/отчёта (YYYY-MM-DD), для начислений с занятий.
  final String? accrualDate;

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
    this.accrualDate,
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
      accrualDate: json['accrual_date']?.toString(),
    );
  }

  bool get isCredit => amount > 0;

  bool get isLessonIncome => type == 'lesson_income';

  /// «за 05.06.2026» — из accrual_date или из description.
  String? get accrualDayLabel {
    final iso = accrualDate;
    if (iso != null && iso.length >= 10) {
      final parts = iso.substring(0, 10).split('-');
      if (parts.length == 3) {
        return 'за ${parts[2]}.${parts[1]}.${parts[0]}';
      }
    }
    final d = description.trim();
    if (d.startsWith('за ')) return d;
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(d);
    if (m != null) {
      return 'за ${m.group(3)}.${m.group(2)}.${m.group(1)}';
    }
    return d.isNotEmpty ? d : null;
  }
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
