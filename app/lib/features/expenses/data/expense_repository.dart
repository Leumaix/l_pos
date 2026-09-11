import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/business_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../shift/data/shift_repository.dart';
import '../domain/expense.dart';

/// Abstract seam for recording an expense — mirrors CheckoutRepository's
/// shape (a fresh id minted up front, then one atomic commit). A
/// standalone repository, not a method on ShiftRepository/SalesRepository:
/// same one-repository-per-concern convention as the rest of this app —
/// expenses are their own bounded concern, even though a cash expense
/// also touches the shift's running totals.
abstract class ExpenseRepository {
  /// A fresh, globally-unique expense id, minted before the [Expense]
  /// itself is built (buildExpense needs an id up front, same as
  /// buildSale).
  String newExpenseId();

  /// Commits the expense record and, for a [ExpensePaymentMethod.cash]
  /// expense only, the shift's running expenseTotalNaira — one atomic
  /// write. Transfer/other expenses touch nothing but the expense doc
  /// itself; they never move real cash, so there's no till total to
  /// update and no shift needs to be open at all.
  ///
  /// Throws [NoShiftOpenException] if [expense.method] is cash and no
  /// shift is currently open — mirrors CheckoutRepository.commitSale's
  /// same guard; firestore.rules independently enforces the same
  /// boundary server-side.
  Future<void> commitExpense({required Expense expense});
}

/// In-memory stand-in. Takes a concrete FakeShiftRepository (not the
/// abstract ShiftRepository) for the same reason FakeCheckoutRepository
/// does — debugApplyExpenseTotal is fake-only test plumbing; the real
/// equivalent is inlined directly into FirebaseExpenseRepository's own
/// transaction, never a standalone ShiftRepository method.
class FakeExpenseRepository implements ExpenseRepository {
  final FakeShiftRepository _shift;
  final List<Expense> _expenses = [];

  FakeExpenseRepository({required this._shift});

  int _idCounter = 0;

  @override
  String newExpenseId() => 'expense-fake-${_idCounter++}';

  @override
  Future<void> commitExpense({required Expense expense}) async {
    if (expense.method == ExpensePaymentMethod.cash) {
      // Throws NoShiftOpenException itself if nothing is open — mirrors
      // FirebaseExpenseRepository.commitExpense's own guard.
      _shift.debugApplyExpenseTotal(amountNaira: expense.amountNaira);
    }
    _expenses.add(expense);
  }

  /// Test-only visibility into what's been recorded so far.
  List<Expense> get debugExpenses => List.unmodifiable(_expenses);
}

class FirebaseExpenseRepository implements ExpenseRepository {
  final AuthRepository _firebaseAuth;

  FirebaseExpenseRepository(this._firebaseAuth);

  FirebaseFirestore get _firestore {
    final firestore = _firebaseAuth.activeFirestore;
    if (firestore == null) {
      throw StateError('ExpenseRepository used with nobody currently signed in.');
    }
    return firestore;
  }

  CollectionReference<Map<String, dynamic>> get _expensesCollection =>
      _firestore.collection('businesses/$kBusinessId/expenses');

  DocumentReference<Map<String, dynamic>> get _shiftStateDoc =>
      _firestore.doc('businesses/$kBusinessId/shiftState/current');

  @override
  String newExpenseId() => _expensesCollection.doc().id;

  @override
  Future<void> commitExpense({required Expense expense}) async {
    await _firestore.runTransaction((transaction) async {
      // All reads first — a Firestore transaction requires it. Only a
      // cash expense needs a shift open at all; transfer/other never
      // touch shiftState.
      if (expense.method == ExpensePaymentMethod.cash) {
        final shiftSnapshot = await transaction.get(_shiftStateDoc);
        if (!shiftSnapshot.exists) throw const NoShiftOpenException();
      }

      transaction.set(_expensesCollection.doc(expense.id), _expenseToDoc(expense));

      if (expense.method == ExpensePaymentMethod.cash) {
        transaction.update(_shiftStateDoc, {
          'expenseTotalNaira': FieldValue.increment(expense.amountNaira),
          // Lets firestore.rules verify this update is paired with THIS
          // exact expense — same anti-replay pairing pattern lastSaleId
          // already uses. See that rule's own comment for the fraud
          // vector this closes; here it's "inflate expenseTotalNaira to
          // justify pocketing cash and covering a drawer shortfall."
          'lastExpenseId': expense.id,
        });
      }
    });
  }

  static Map<String, dynamic> _expenseToDoc(Expense expense) => {
    'amountNaira': expense.amountNaira,
    'paymentMethod': expense.method.name,
    'category': expense.category.name,
    'note': expense.note,
    'staffId': expense.staffId,
    'staffName': expense.staffName,
    'shiftId': expense.shiftId,
    'createdAt': FieldValue.serverTimestamp(),
  };
}
