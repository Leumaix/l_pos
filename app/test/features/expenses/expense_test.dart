import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/expenses/domain/expense.dart';

void main() {
  final createdAt = DateTime(2026, 9, 11, 14, 0);

  Expense build({
    int amountNaira = 5000,
    ExpensePaymentMethod method = ExpensePaymentMethod.cash,
    ExpenseCategory category = ExpenseCategory.fuel,
    String? note,
    String? shiftId = 'hist-1',
  }) {
    return buildExpense(
      amountNaira: amountNaira,
      method: method,
      category: category,
      note: note,
      staffId: 'staff-1',
      staffName: 'Ifeoma',
      id: 'expense-1',
      shiftId: shiftId,
      createdAt: createdAt,
    );
  }

  group('amount validation', () {
    test('zero amount throws InvalidExpenseAmountException', () {
      expect(() => build(amountNaira: 0), throwsA(isA<InvalidExpenseAmountException>()));
    });

    test('negative amount throws InvalidExpenseAmountException', () {
      expect(() => build(amountNaira: -500), throwsA(isA<InvalidExpenseAmountException>()));
    });

    test('a positive amount succeeds', () {
      expect(build(amountNaira: 5000).amountNaira, 5000);
    });
  });

  group('category "other" requires a note', () {
    test('throws ExpenseNoteRequiredException with no note', () {
      expect(
        () => build(category: ExpenseCategory.other, note: null, method: ExpensePaymentMethod.transfer),
        throwsA(isA<ExpenseNoteRequiredException>()),
      );
    });

    test('throws ExpenseNoteRequiredException with a blank/whitespace-only note', () {
      expect(
        () => build(category: ExpenseCategory.other, note: '   ', method: ExpensePaymentMethod.transfer),
        throwsA(isA<ExpenseNoteRequiredException>()),
      );
    });

    test('succeeds with a real note', () {
      final expense = build(category: ExpenseCategory.other, note: 'Signboard repair', method: ExpensePaymentMethod.transfer);
      expect(expense.note, 'Signboard repair');
    });

    test('a fixed category needs no note at all', () {
      expect(build(category: ExpenseCategory.fuel, note: null).note, isNull);
    });
  });

  group('cash expenses require a shiftId', () {
    test('throws ShiftRequiredForCashExpenseException when method is cash and shiftId is null', () {
      expect(
        () => build(method: ExpensePaymentMethod.cash, shiftId: null),
        throwsA(isA<ShiftRequiredForCashExpenseException>()),
      );
    });

    test('succeeds with a shiftId, and it is carried onto the record', () {
      expect(build(method: ExpensePaymentMethod.cash, shiftId: 'hist-42').shiftId, 'hist-42');
    });

    test('transfer/other expenses need no shiftId at all', () {
      expect(build(method: ExpensePaymentMethod.transfer, shiftId: null).shiftId, isNull);
      expect(build(method: ExpensePaymentMethod.other, shiftId: null).shiftId, isNull);
    });
  });

  test('constructs the full record on the happy path', () {
    final expense = build(
      amountNaira: 12000,
      method: ExpensePaymentMethod.cash,
      category: ExpenseCategory.maintenance,
      shiftId: 'hist-7',
    );
    expect(expense.id, 'expense-1');
    expect(expense.amountNaira, 12000);
    expect(expense.method, ExpensePaymentMethod.cash);
    expect(expense.category, ExpenseCategory.maintenance);
    expect(expense.staffId, 'staff-1');
    expect(expense.staffName, 'Ifeoma');
    expect(expense.shiftId, 'hist-7');
    expect(expense.createdAt, createdAt);
  });
}
