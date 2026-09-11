import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/auth_repository.dart';
import 'package:leumadepos/features/expenses/application/expense_controller.dart';
import 'package:leumadepos/features/expenses/application/expense_providers.dart';
import 'package:leumadepos/features/expenses/data/expense_repository.dart';
import 'package:leumadepos/features/expenses/domain/expense.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';

const _testStaff = AppUser(
  uid: 'staff-1',
  name: 'Ifeoma',
  email: 'ifeoma@leumadepos.test',
  role: 'attendant',
);

void main() {
  late FakeShiftRepository shift;
  late FakeExpenseRepository expenses;
  late ProviderContainer container;

  Future<ProviderContainer> buildContainer({bool openShift = true}) async {
    shift = FakeShiftRepository(openShift: openShift);
    expenses = FakeExpenseRepository(shift: shift);
    final c = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(_testStaff)),
        shiftRepositoryProvider.overrideWithValue(shift),
        expenseRepositoryProvider.overrideWithValue(expenses),
      ],
    );
    // authStateProvider is a StreamProvider; warm it up so it's already
    // AsyncData by the time recordExpense reads it — same fix
    // checkout_controller_test.dart already needs for the same reason.
    await c.read(authStateProvider.future);
    return c;
  }

  tearDown(() => container.dispose());

  test('a cash expense increments the shift expenseTotalNaira and carries the current shiftId', () async {
    container = await buildContainer();

    final expense = await container.read(expenseControllerProvider).recordExpense(
      amountNaira: 4000,
      method: ExpensePaymentMethod.cash,
      category: ExpenseCategory.fuel,
    );

    expect(expense.shiftId, shift.currentShift!.plannedHistoryId);
    expect(expenses.debugExpenses, hasLength(1));
    expect(shift.currentShift!.expenseTotalNaira, 4000);
  });

  test('a transfer expense never touches the shift, and works even with no shift open', () async {
    container = await buildContainer(openShift: false);

    final expense = await container.read(expenseControllerProvider).recordExpense(
      amountNaira: 7000,
      method: ExpensePaymentMethod.transfer,
      category: ExpenseCategory.supplies,
    );

    expect(expense.shiftId, isNull);
    expect(expenses.debugExpenses, hasLength(1));
  });

  test('an "other" expense with no note throws before ever reaching the repository', () async {
    container = await buildContainer();

    expect(
      () => container.read(expenseControllerProvider).recordExpense(
        amountNaira: 3000,
        method: ExpensePaymentMethod.other,
        category: ExpenseCategory.other,
      ),
      throwsA(isA<ExpenseNoteRequiredException>()),
    );
    expect(expenses.debugExpenses, isEmpty);
  });

  test('a cash expense with no shift open throws NoShiftOpenException', () async {
    container = await buildContainer(openShift: false);

    expect(
      () => container.read(expenseControllerProvider).recordExpense(
        amountNaira: 4000,
        method: ExpensePaymentMethod.cash,
        category: ExpenseCategory.fuel,
      ),
      throwsA(isA<NoShiftOpenException>()),
    );
    expect(expenses.debugExpenses, isEmpty);
  });

  test('two cash expenses in the same shift accumulate', () async {
    container = await buildContainer();
    final controller = container.read(expenseControllerProvider);

    await controller.recordExpense(amountNaira: 2000, method: ExpensePaymentMethod.cash, category: ExpenseCategory.fuel);
    await controller.recordExpense(amountNaira: 1500, method: ExpensePaymentMethod.cash, category: ExpenseCategory.transport);

    expect(shift.currentShift!.expenseTotalNaira, 3500);
    expect(expenses.debugExpenses, hasLength(2));
  });
}
