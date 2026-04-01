/// Месячный отчёт по зарплате: доход, поздние отчёты, 50% преподавателю.
class MonthlySalaryReport {
  final int year;
  final int month;
  final String firstDay;
  final String lastDay;
  final double totalAll;
  final double lateReportsAmount;
  final double incomeCounted;
  final int salary;
  final List<ReportDayRow> reportBreakdown;
  final double lessonsWithoutReportAmount;
  /// Занятия в месяце, сгруппированные по цене за занятие (тариф).
  final List<LessonPriceCountRow> lessonsByPrice;

  const MonthlySalaryReport({
    required this.year,
    required this.month,
    required this.firstDay,
    required this.lastDay,
    required this.totalAll,
    required this.lateReportsAmount,
    required this.incomeCounted,
    required this.salary,
    required this.reportBreakdown,
    required this.lessonsWithoutReportAmount,
    this.lessonsByPrice = const [],
  });

  factory MonthlySalaryReport.fromJson(Map<String, dynamic> json) {
    final list = json['report_breakdown'] as List<dynamic>?;
    final byPrice = json['lessons_by_price'] as List<dynamic>?;
    return MonthlySalaryReport(
      year: json['year'] as int,
      month: json['month'] as int,
      firstDay: json['first_day'] as String,
      lastDay: json['last_day'] as String,
      totalAll: _numToDouble(json['total_all']),
      lateReportsAmount: _numToDouble(json['late_reports_amount']),
      incomeCounted: _numToDouble(json['income_counted']),
      salary: json['salary'] is int ? json['salary'] as int : (_numToDouble(json['salary'])).round(),
      reportBreakdown: list != null
          ? list.map((e) => ReportDayRow.fromJson(e as Map<String, dynamic>)).toList()
          : const [],
      lessonsWithoutReportAmount: _numToDouble(json['lessons_without_report_amount']),
      lessonsByPrice: byPrice != null
          ? byPrice.map((e) => LessonPriceCountRow.fromJson(e as Map<String, dynamic>)).toList()
          : const [],
    );
  }

  int get totalLessonsInMonth =>
      lessonsByPrice.fold<int>(0, (sum, row) => sum + row.lessonsCount);
}

double _numToDouble(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v.toDouble();
  if (v is double) return v;
  return double.tryParse(v.toString()) ?? 0;
}

/// Одна строка: цена занятия и сколько таких занятий в месяце.
class LessonPriceCountRow {
  final double price;
  final int lessonsCount;

  const LessonPriceCountRow({
    required this.price,
    required this.lessonsCount,
  });

  factory LessonPriceCountRow.fromJson(Map<String, dynamic> json) {
    final c = json['lessons_count'];
    return LessonPriceCountRow(
      price: _numToDouble(json['price']),
      lessonsCount: c is int ? c : int.tryParse(c?.toString() ?? '') ?? 0,
    );
  }
}

/// Один день (отчёт) в разбивке: дата, поздний/нет, сумма.
class ReportDayRow {
  final int reportId;
  final String reportDate;
  final bool isLate;
  final double amount;

  const ReportDayRow({
    required this.reportId,
    required this.reportDate,
    required this.isLate,
    required this.amount,
  });

  factory ReportDayRow.fromJson(Map<String, dynamic> json) {
    return ReportDayRow(
      reportId: json['report_id'] as int? ?? 0,
      reportDate: json['report_date'] as String? ?? '',
      isLate: json['is_late'] == true,
      amount: _numToDouble(json['amount']),
    );
  }
}
