class Student {
  final int id;
  final String name;
  final String? parentName;
  final String? phone;
  final String? email;
  final String? notes;
  final double balance;
  final bool payByBankTransfer;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Student({
    required this.id,
    required this.name,
    this.parentName,
    this.phone,
    this.email,
    this.notes,
    required this.balance,
    this.payByBankTransfer = false,
    required this.createdAt,
    this.updatedAt,
  });

  static int _parseRequiredInt(dynamic v, String fieldName) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final parsed = int.tryParse(v?.toString() ?? '');
    if (parsed == null) {
      throw FormatException('Invalid $fieldName');
    }
    return parsed;
  }

  static double _parseDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static bool _parseBool(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: _parseRequiredInt(json['id'], 'student id'),
      name: json['name']?.toString() ?? '',
      parentName: json['parent_name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      notes: json['notes'] as String?,
      balance: _parseDouble(json['balance']),
      payByBankTransfer: _parseBool(json['pay_by_bank_transfer']),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  bool get isDebtor => balance < 0;
}

