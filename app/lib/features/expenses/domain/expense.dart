/// How an expense was paid. Deliberately a separate enum from
/// [PaymentMethod] (sell/domain/sale.dart) — expenses have no card/
/// customerAccount option, but do have 'other' (a payment method sales
/// never needs), so the two lists were never going to be the same set.
enum ExpensePaymentMethod { cash, transfer, other }

/// A fixed list, not free text — Reports/rules both need a bounded set
/// to group and validate against. 'other' is the one escape hatch, and
/// it requires [Expense.note] to say what it actually was (see
/// [buildExpense]).
enum ExpenseCategory { fuel, transport, maintenance, supplies, other }

/// A single recorded business expense — fuel, transport, maintenance,
/// supplies, or something else, logged by any active staff member (not
/// owner-only, matching how selling/restocking already work). Only a
/// [ExpensePaymentMethod.cash] expense affects the till — see
/// [shiftId]/the shift feature's `expenseTotalNaira` — a transfer/other
/// expense is a record only, it never moved cash out of this drawer.
class Expense {
  final String id;
  final int amountNaira;
  final ExpensePaymentMethod method;
  final ExpenseCategory category;

  /// Required when [category] is [ExpenseCategory.other] — the one place
  /// a category alone doesn't say what the money was for.
  final String? note;

  final String staffId;
  final String staffName;

  /// The currently open shift's stable id (OpenShift.plannedHistoryId —
  /// see that field's own doc comment for why it's reused here rather
  /// than a new concept). Required when [method] is
  /// [ExpensePaymentMethod.cash] — a transfer/other expense isn't tied
  /// to a till, so it carries no shift at all, open or not.
  final String? shiftId;

  final DateTime createdAt;

  const Expense({
    required this.id,
    required this.amountNaira,
    required this.method,
    required this.category,
    this.note,
    required this.staffId,
    required this.staffName,
    this.shiftId,
    required this.createdAt,
  });
}

/// Thrown when [buildExpense] is given an amount that isn't a real
/// expense — zero or negative. Unlike a sale's payment lines, an expense
/// has no "change given" concept, so there's no legitimate negative case
/// here at all.
class InvalidExpenseAmountException implements Exception {
  final int amountNaira;
  const InvalidExpenseAmountException(this.amountNaira);
}

/// Thrown when [ExpenseCategory.other] is chosen with no (or blank)
/// [Expense.note] — the one place a category alone doesn't explain what
/// the money was for.
class ExpenseNoteRequiredException implements Exception {
  const ExpenseNoteRequiredException();
}

/// Thrown when [buildExpense] is asked for a [ExpensePaymentMethod.cash]
/// expense with no [Expense.shiftId] supplied. This is a programmer-error
/// guard, not a normal-flow error path — the caller (ExpenseController)
/// is responsible for resolving shiftId from the currently open shift
/// (or rejecting with the shift feature's own NoShiftOpenException)
/// before ever calling buildExpense; this only fires if that resolution
/// step is skipped.
class ShiftRequiredForCashExpenseException implements Exception {
  const ShiftRequiredForCashExpenseException();
}

/// Pure: validates and constructs the [Expense] record. Mirrors
/// buildSale's shape (sell/domain/checkout.dart) — never mutates
/// anything, the caller (ExpenseController/ExpenseRepository) handles
/// the actual commit.
Expense buildExpense({
  required int amountNaira,
  required ExpensePaymentMethod method,
  required ExpenseCategory category,
  String? note,
  required String staffId,
  required String staffName,
  required String id,
  String? shiftId,
  required DateTime createdAt,
}) {
  if (amountNaira <= 0) throw InvalidExpenseAmountException(amountNaira);

  if (category == ExpenseCategory.other && (note == null || note.trim().isEmpty)) {
    throw const ExpenseNoteRequiredException();
  }

  if (method == ExpensePaymentMethod.cash && shiftId == null) {
    throw const ShiftRequiredForCashExpenseException();
  }

  return Expense(
    id: id,
    amountNaira: amountNaira,
    method: method,
    category: category,
    note: note,
    staffId: staffId,
    staffName: staffName,
    shiftId: shiftId,
    createdAt: createdAt,
  );
}
