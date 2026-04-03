class Transaction {
  final int id;
  final int studentId;
  final double amount;
  final String type; // 'deposit', 'lesson', 'refund'
  final String? description;
  final int? lessonId;
  final int createdBy;
  final DateTime createdAt;
  final DateTime? lessonDate;
  final String? lessonTime;

  Transaction({
    required this.id,
    required this.studentId,
    required this.amount,
    required this.type,
    this.description,
    this.lessonId,
    required this.createdBy,
    required this.createdAt,
    this.lessonDate,
    this.lessonTime,
  });

  // Определяет, является ли пополнение ручным (наличка) или из банка
  bool get isManualDeposit {
    if (type != 'deposit') return false;
    if (description == null) return true; // По умолчанию считаем ручным
    final desc = description!.toLowerCase();
    // Если в описании есть "из выписки" или "из банка" - это из банка
    return !desc.contains('из выписки') && !desc.contains('из банка');
  }

  bool get isBankDeposit {
    if (type != 'deposit') return false;
    if (description == null) return false;
    final desc = description!.toLowerCase();
    return desc.contains('из выписки') || desc.contains('из банка');
  }

  String get depositTypeLabel {
    if (type != 'deposit') return '';
    if (isBankDeposit) return 'Банковский перевод';
    return 'Наличные';
  }

  static int _parseRequiredInt(dynamic v, String fieldName) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final parsed = int.tryParse(v?.toString() ?? '');
    if (parsed == null) {
      throw FormatException('Invalid $fieldName');
    }
    return parsed;
  }

  static int? _parseOptionalInt(dynamic v) {
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

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: _parseRequiredInt(json['id'], 'transaction id'),
      studentId: _parseRequiredInt(json['student_id'], 'student_id'),
      amount: _parseDouble(json['amount']),
      type: json['type']?.toString() ?? '',
      description: json['description'] as String?,
      lessonId: _parseOptionalInt(json['lesson_id']),
      createdBy: _parseRequiredInt(json['created_by'], 'created_by'),
      createdAt: DateTime.parse(json['created_at']),
      lessonDate: json['lesson_date'] != null 
          ? DateTime.parse(json['lesson_date'])
          : null,
      lessonTime: json['lesson_time'] as String?,
    );
  }
}

