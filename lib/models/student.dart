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

  factory Student.fromJson(Map<String, dynamic> json) {
    final payByBank = json['pay_by_bank_transfer'];
    final payByBankTransfer = payByBank == true || payByBank == 'true';
    return Student(
      id: json['id'] as int,
      name: json['name'] as String,
      parentName: json['parent_name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      notes: json['notes'] as String?,
      balance: (json['balance'] ?? 0.0) is double 
          ? json['balance'] as double 
          : double.tryParse(json['balance'].toString()) ?? 0.0,
      payByBankTransfer: payByBankTransfer,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  bool get isDebtor => balance < 0;
}

