import 'package:flutter_test/flutter_test.dart';
import 'package:my_chat_app/models/monthly_salary_report.dart';

void main() {
  group('MonthlySalaryReport.fromJson', () {
    test('основные поля', () {
      final r = MonthlySalaryReport.fromJson({
        'year': 2025,
        'month': 3,
        'first_day': '2025-03-01',
        'last_day': '2025-03-31',
        'total_all': 100000,
        'late_reports_amount': 10000,
        'income_counted': 90000,
        'salary': 45000,
        'report_breakdown': [],
        'lessons_without_report_amount': 0,
        'lessons_by_price': [
          {'price': 2000, 'lessons_count': 120},
          {'price': 2100, 'lessons_count': 40},
        ],
      });
      expect(r.year, 2025);
      expect(r.month, 3);
      expect(r.totalAll, 100000.0);
      expect(r.lateReportsAmount, 10000.0);
      expect(r.incomeCounted, 90000.0);
      expect(r.salary, 45000);
      expect(r.reportBreakdown, isEmpty);
      expect(r.lessonsByPrice.length, 2);
      expect(r.lessonsByPrice[0].price, 2000.0);
      expect(r.lessonsByPrice[0].lessonsCount, 120);
      expect(r.lessonsByPrice[1].lessonsCount, 40);
      expect(r.totalLessonsInMonth, 160);
    });

    test('report_breakdown парсится', () {
      final r = MonthlySalaryReport.fromJson({
        'year': 2025,
        'month': 3,
        'first_day': '2025-03-01',
        'last_day': '2025-03-31',
        'total_all': 0,
        'late_reports_amount': 0,
        'income_counted': 0,
        'salary': 0,
        'lessons_without_report_amount': 0,
        'report_breakdown': [
          {'report_id': 1, 'report_date': '2025-03-01', 'is_late': false, 'amount': 5000},
          {'report_id': 2, 'report_date': '2025-03-02', 'is_late': true, 'amount': 3000},
        ],
      });
      expect(r.reportBreakdown.length, 2);
      expect(r.reportBreakdown[0].reportId, 1);
      expect(r.reportBreakdown[0].isLate, false);
      expect(r.reportBreakdown[1].isLate, true);
    });
  });

  group('ReportDayRow.fromJson', () {
    test('парсит строку разбивки', () {
      final row = ReportDayRow.fromJson({
        'report_id': 10,
        'report_date': '2025-03-05',
        'is_late': true,
        'amount': 2500.5,
      });
      expect(row.reportId, 10);
      expect(row.reportDate, '2025-03-05');
      expect(row.isLate, true);
      expect(row.amount, 2500.5);
    });
  });

  // Реальные wire-формы: сервер отдаёт денежные агрегаты и цены как строки
  // ("100000", "2000.00"), а не как числа (см. аудит M64/H15). Модель обязана
  // распарсить строку в корректное числовое значение.
  group('MonthlySalaryReport.fromJson — деньги строкой (реальный wire-shape)', () {
    test('total_all/late/income/salary/price/amount строками', () {
      final r = MonthlySalaryReport.fromJson({
        'year': 2025,
        'month': 3,
        'first_day': '2025-03-01',
        'last_day': '2025-03-31',
        'total_all': '100000',
        'late_reports_amount': '10000.00',
        'income_counted': '90000.00',
        'bank_transfer_deduction': '300.00',
        'salary': '45000',
        'lessons_without_report_amount': '0.00',
        'report_breakdown': [
          {
            'report_id': 1,
            'report_date': '2025-03-01',
            'is_late': false,
            'amount': '5000.00',
          },
        ],
        'lessons_by_price': [
          {'price': '2000.00', 'lessons_count': '120'},
        ],
      });
      expect(r.totalAll, 100000.0);
      expect(r.lateReportsAmount, 10000.0);
      expect(r.incomeCounted, 90000.0);
      expect(r.bankTransferDeduction, 300.0);
      expect(r.salary, 45000);
      expect(r.lessonsWithoutReportAmount, 0.0);
      expect(r.reportBreakdown.single.amount, 5000.0);
      expect(r.lessonsByPrice.single.price, 2000.0);
      expect(r.lessonsByPrice.single.lessonsCount, 120);
      expect(r.totalLessonsInMonth, 120);
    });
  });
}
