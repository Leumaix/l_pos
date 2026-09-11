import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../shift/application/shift_providers.dart';
import '../../shift/data/shift_repository.dart';
import '../domain/expense.dart';
import 'expense_providers.dart';

/// Records a single expense — mirrors CheckoutController.completeSale's
/// shape exactly (read the signed-in staff, resolve whatever else the
/// domain builder needs, mint an id, build, commit).
///
/// Unlike checkout, this screen is reached from Home directly (a Quick
/// Action), not primed by Sell first — so a cash expense resolves the
/// current shift via ShiftRepository.fetchCurrentShift(), the one-shot
/// authoritative read, not the cached currentShift getter. Same caution
/// CloseDayController.preparePreview already uses, and for the same
/// reason: currentShift can still be showing its cold-start null the
/// first time it's accessed in a session that never visited Sell.
class ExpenseController {
  final Ref ref;

  ExpenseController(this.ref);

  Future<Expense> recordExpense({
    required int amountNaira,
    required ExpensePaymentMethod method,
    required ExpenseCategory category,
    String? note,
  }) async {
    final staff = ref.read(authStateProvider).valueOrNull;
    if (staff == null) {
      throw StateError('recordExpense called with no signed-in staff member');
    }

    String? shiftId;
    if (method == ExpensePaymentMethod.cash) {
      final shift = await ref.read(shiftRepositoryProvider).fetchCurrentShift();
      if (shift == null) throw const NoShiftOpenException();
      shiftId = shift.plannedHistoryId;
    }

    final expenses = ref.read(expenseRepositoryProvider);
    final expense = buildExpense(
      amountNaira: amountNaira,
      method: method,
      category: category,
      note: note,
      staffId: staff.uid,
      staffName: staff.name,
      id: expenses.newExpenseId(),
      shiftId: shiftId,
      createdAt: DateTime.now(),
    );

    await expenses.commitExpense(expense: expense);
    return expense;
  }
}

final expenseControllerProvider = Provider((ref) => ExpenseController(ref));
