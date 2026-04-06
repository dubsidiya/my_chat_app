/// Структура слота дневного отчёта для API `slots` (POST/PUT /reports).
class ReportStructuredStudent {
  final int studentId;
  final double price;
  final String status;

  const ReportStructuredStudent({
    required this.studentId,
    required this.price,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'price': price,
        'status': status,
      };
}

class ReportStructuredSlot {
  final String timeStart;
  final String timeEnd;
  final List<ReportStructuredStudent> students;

  const ReportStructuredSlot({
    required this.timeStart,
    required this.timeEnd,
    required this.students,
  });

  Map<String, dynamic> toJson() => {
        'timeStart': timeStart,
        'timeEnd': timeEnd,
        'students': students.map((e) => e.toJson()).toList(),
      };
}
