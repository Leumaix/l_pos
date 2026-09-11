import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shift/data/shift_repository.dart';
import '../domain/expense.dart';
import 'expense_controller.dart';

class RecordExpenseFormState {
  final String amountInput;
  final ExpensePaymentMethod? method;
  final ExpenseCategory? category;
  final String note;
  final bool submitting;
  final String? errorMessage;
  final bool justRecorded;

  const RecordExpenseFormState({
    this.amountInput = '',
    this.method,
    this.category,
    this.note = '',
    this.submitting = false,
    this.errorMessage,
    this.justRecorded = false,
  });

  int? get amountNaira => amountInput.isEmpty ? null : int.tryParse(amountInput);

  /// Mirrors buildExpense's own validation exactly (see
  /// domain/expense.dart) — a UI-side rejection and a buildExpense
  /// exception should never be in conflict, same principle split-tender's
  /// checkout UI used.
  bool get canSubmit =>
      !submitting &&
      (amountNaira ?? 0) > 0 &&
      method != null &&
      category != null &&
      (category != ExpenseCategory.other || note.trim().isNotEmpty);

  RecordExpenseFormState copyWith({
    String? amountInput,
    ExpensePaymentMethod? method,
    ExpenseCategory? category,
    String? note,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
    bool? justRecorded,
  }) {
    return RecordExpenseFormState(
      amountInput: amountInput ?? this.amountInput,
      method: method ?? this.method,
      category: category ?? this.category,
      note: note ?? this.note,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      justRecorded: justRecorded ?? this.justRecorded,
    );
  }
}

/// Any active staff member — not owner-only. No confirmation dialog (see
/// OpenDayController for the same "declare and go" shape); unlike Close
/// Day, there's nothing here worth a second confirmation step over.
class RecordExpenseController extends StateNotifier<RecordExpenseFormState> {
  final Ref ref;

  RecordExpenseController(this.ref) : super(const RecordExpenseFormState());

  void setMethod(ExpensePaymentMethod method) {
    state = state.copyWith(method: method, clearError: true, justRecorded: false);
  }

  void setCategory(ExpenseCategory category) {
    state = state.copyWith(category: category, clearError: true, justRecorded: false);
  }

  void setNote(String value) {
    state = state.copyWith(note: value, clearError: true, justRecorded: false);
  }

  /// Same keypad-assembly shape as PaymentScreen's own _onAmountKey —
  /// whole naira only (no '.'), a sane max length, backspace support.
  void onAmountKey(String key) {
    var input = state.amountInput;
    if (key == 'back') {
      if (input.isNotEmpty) input = input.substring(0, input.length - 1);
    } else if (key == '.') {
      // whole naira only
    } else if (input.length < 9) {
      input += key;
    }
    state = state.copyWith(amountInput: input, clearError: true, justRecorded: false);
  }

  Future<void> submit() async {
    if (!state.canSubmit) return;

    state = state.copyWith(submitting: true, clearError: true);
    try {
      await ref
          .read(expenseControllerProvider)
          .recordExpense(
            amountNaira: state.amountNaira!,
            method: state.method!,
            category: state.category!,
            note: state.category == ExpenseCategory.other ? state.note.trim() : null,
          );
      state = const RecordExpenseFormState(justRecorded: true);
    } on NoShiftOpenException {
      state = state.copyWith(
        submitting: false,
        errorMessage: 'No shift is currently open — a cash expense needs one.',
      );
    } catch (_) {
      state = state.copyWith(submitting: false, errorMessage: 'Could not record that expense. Try again.');
    }
  }
}

final recordExpenseControllerProvider =
    StateNotifierProvider.autoDispose<RecordExpenseController, RecordExpenseFormState>(
      (ref) => RecordExpenseController(ref),
    );
