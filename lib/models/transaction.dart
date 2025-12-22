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

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      studentId: json['student_id'] is int 
          ? json['student_id'] 
          : int.parse(json['student_id'].toString()),
      amount: json['amount'] is double 
          ? json['amount'] 
          : double.parse(json['amount'].toString()),
      type: json['type'] as String,
      description: json['description'] as String?,
      lessonId: json['lesson_id'] != null 
          ? (json['lesson_id'] is int 
              ? json['lesson_id'] 
              : int.parse(json['lesson_id'].toString()))
          : null,
      createdBy: json['created_by'] is int 
          ? json['created_by'] 
          : int.parse(json['created_by'].toString()),
      createdAt: DateTime.parse(json['created_at']),
      lessonDate: json['lesson_date'] != null 
          ? DateTime.parse(json['lesson_date'])
          : null,
      lessonTime: json['lesson_time'] as String?,
    );
  }
}

