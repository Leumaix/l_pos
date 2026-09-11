import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/expenses/domain/expense.dart';
import 'package:leumadepos/features/expenses/domain/expenses_report.dart';
import 'package:leumadepos/features/reports/domain/sales_report.dart';

Expense _expenseAt(DateTime when, {int amountNaira = 1000}) {
  return Expense(
    id: 'exp-${when.millisecondsSinceEpoch}',
    amountNaira: amountNaira,
    method: ExpensePaymentMethod.transfer,
    category: ExpenseCategory.fuel,
    staffId: 's1',
    staffName: 'Staff',
    createdAt: when,
  );
}

void main() {
  final now = DateTime(2026, 9, 15, 14, 0);

  test('totalForRange sums only expenses within the range — today', () {
    final expenses = [
      _expenseAt(now, amountNaira: 2000), // today
      _expenseAt(now.subtract(const Duration(days: 1)), amountNaira: 5000), // yesterday, excluded
    ];
    final report = buildExpensesReport(expenses, range: ReportRange.today, now: now);
    expect(report.totalForRange, 2000);
  });

  test('week range includes the last 7 days, inclusive of today', () {
    final expenses = [
      _expenseAt(now, amountNaira: 1000),
      _expenseAt(now.subtract(const Duration(days: 6)), amountNaira: 500),
      _expenseAt(now.subtract(const Duration(days: 7)), amountNaira: 999999), // just outside, excluded
    ];
    final report = buildExpensesReport(expenses, range: ReportRange.week, now: now);
    expect(report.totalForRange, 1500);
  });

  test('an empty list reports a zero total, not an error', () {
    final report = buildExpensesReport(const [], range: ReportRange.today, now: now);
    expect(report.totalForRange, 0);
  });

  test('every payment method counts toward the total — this is spend, not till cash', () {
    final expenses = [
      Expense(
        id: 'e1',
        amountNaira: 1000,
        method: ExpensePaymentMethod.cash,
        category: ExpenseCategory.fuel,
        staffId: 's1',
        staffName: 'Staff',
        shiftId: 'hist-1',
        createdAt: now,
      ),
      Expense(
        id: 'e2',
        amountNaira: 2000,
        method: ExpensePaymentMethod.transfer,
        category: ExpenseCategory.supplies,
        staffId: 's1',
        staffName: 'Staff',
        createdAt: now,
      ),
      Expense(
        id: 'e3',
        amountNaira: 500,
        method: ExpensePaymentMethod.other,
        category: ExpenseCategory.other,
        note: 'Misc',
        staffId: 's1',
        staffName: 'Staff',
        createdAt: now,
      ),
    ];
    final report = buildExpensesReport(expenses, range: ReportRange.today, now: now);
    expect(report.totalForRange, 3500);
  });
}
