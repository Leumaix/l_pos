import '../../reports/domain/sales_report.dart' show ReportRange;
import 'expense.dart';

class ExpensesReport {
  final int totalForRange;

  const ExpensesReport({required this.totalForRange});
}

bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

bool _inRange(DateTime createdAt, ReportRange range, DateTime now) {
  switch (range) {
    case ReportRange.today:
      return _isSameDay(createdAt, now);
    case ReportRange.week:
      final start = _startOfDay(now).subtract(const Duration(days: 6));
      return !createdAt.isBefore(start);
    case ReportRange.month:
      final start = _startOfDay(now).subtract(const Duration(days: 29));
      return !createdAt.isBefore(start);
  }
}

/// Pure aggregation over an already-fetched expenses list — mirrors
/// buildSalesReport's exact shape (sell/../reports/domain/sales_report.dart),
/// same ReportRange, same _inRange filtering. Every expense counts here
/// regardless of paymentMethod — this is spend, not till cash — unlike
/// shiftState/current.expenseTotalNaira, which is cash-only.
ExpensesReport buildExpensesReport(List<Expense> expenses, {required ReportRange range, required DateTime now}) {
  final inRange = expenses.where((expense) => _inRange(expense.createdAt, range, now)).toList();
  final totalForRange = inRange.fold(0, (sum, expense) => sum + expense.amountNaira);
  return ExpensesReport(totalForRange: totalForRange);
}
