import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../shift/data/shift_repository.dart';
import '../domain/gift.dart';
import 'gift_controller.dart';

class RecordGiftFormState {
  final GiftItemType itemType;
  final String? productId;
  final String quantityInput;
  final String reason;
  final String ownerEmail;
  final String ownerPin;
  final bool submitting;
  final String? errorMessage;
  final bool justRecorded;

  const RecordGiftFormState({
    this.itemType = GiftItemType.gas,
    this.productId,
    this.quantityInput = '',
    this.reason = '',
    this.ownerEmail = '',
    this.ownerPin = '',
    this.submitting = false,
    this.errorMessage,
    this.justRecorded = false,
  });

  num? get quantity =>
      quantityInput.isEmpty ? null : num.tryParse(quantityInput);

  RecordGiftFormState copyWith({
    GiftItemType? itemType,
    String? productId,
    bool clearProductId = false,
    String? quantityInput,
    String? reason,
    String? ownerEmail,
    String? ownerPin,
    bool? submitting,
    String? errorMessage,
    bool clearError = false,
    bool? justRecorded,
  }) {
    return RecordGiftFormState(
      itemType: itemType ?? this.itemType,
      productId: clearProductId ? null : (productId ?? this.productId),
      quantityInput: quantityInput ?? this.quantityInput,
      reason: reason ?? this.reason,
      ownerEmail: ownerEmail ?? this.ownerEmail,
      ownerPin: ownerPin ?? this.ownerPin,
      submitting: submitting ?? this.submitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      justRecorded: justRecorded ?? this.justRecorded,
    );
  }
}

/// Any active staff member — not owner-only. Mirrors
/// RecordExpenseController's shape closely; the one real addition is the
/// owner-approval step (see [evaluation]/[canSubmit]), which
/// GiftController.recordGift re-derives and enforces itself regardless of
/// what this controller decided — this is a UI convenience only, never
/// the actual trust boundary (see that controller's own doc comment).
class RecordGiftController extends StateNotifier<RecordGiftFormState> {
  final Ref ref;

  RecordGiftController(this.ref) : super(const RecordGiftFormState());

  /// Null while the quantity/product selection is incomplete — the
  /// screen uses that to keep the approval section hidden until there's
  /// something real to evaluate. Recomputed from current state on every
  /// read (cheap, pure), never cached, so it can never go stale relative
  /// to state.
  GiftEvaluation? get evaluation {
    final quantity = state.quantity;
    if (quantity == null || quantity <= 0) return null;
    if (state.itemType == GiftItemType.product && state.productId == null)
      return null;
    return ref
        .read(giftControllerProvider)
        .evaluateGift(
          itemType: state.itemType,
          productId: state.productId,
          quantity: quantity,
        );
  }

  bool get canSubmit {
    if (state.submitting) return false;
    final quantity = state.quantity;
    if (quantity == null || quantity <= 0) return false;
    if (state.reason.trim().isEmpty) return false;
    if (state.itemType == GiftItemType.product && state.productId == null)
      return false;
    final eval = evaluation;
    if (eval != null && eval.requiresApproval) {
      return state.ownerEmail.trim().isNotEmpty && state.ownerPin.length == 4;
    }
    return true;
  }

  void setItemType(GiftItemType itemType) {
    state = state.copyWith(
      itemType: itemType,
      clearProductId: true,
      quantityInput: '',
      clearError: true,
      justRecorded: false,
    );
  }

  void setProduct(String productId) {
    state = state.copyWith(
      productId: productId,
      clearError: true,
      justRecorded: false,
    );
  }

  /// Same keypad-assembly shape as RecordExpenseController.onAmountKey —
  /// a decimal point is only meaningful for gas (kg); a product gift is
  /// always a whole-unit count.
  void onQuantityKey(String key) {
    var input = state.quantityInput;
    if (key == 'back') {
      if (input.isNotEmpty) input = input.substring(0, input.length - 1);
    } else if (key == '.') {
      if (state.itemType == GiftItemType.gas && !input.contains('.'))
        input += key;
    } else if (input.length < 6) {
      input += key;
    }
    state = state.copyWith(
      quantityInput: input,
      clearError: true,
      justRecorded: false,
    );
  }

  void setReason(String value) {
    state = state.copyWith(
      reason: value,
      clearError: true,
      justRecorded: false,
    );
  }

  void setOwnerEmail(String value) {
    state = state.copyWith(
      ownerEmail: value,
      clearError: true,
      justRecorded: false,
    );
  }

  /// Same shape as LoginController.tapKey — a 4-digit PIN, backspace,
  /// locked out while submitting.
  void tapOwnerPinKey(String key) {
    if (state.submitting) return;
    if (key == 'back') {
      if (state.ownerPin.isEmpty) return;
      state = state.copyWith(
        ownerPin: state.ownerPin.substring(0, state.ownerPin.length - 1),
        clearError: true,
      );
      return;
    }
    if (state.ownerPin.length >= 4) return;
    state = state.copyWith(ownerPin: state.ownerPin + key, clearError: true);
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    final needsApproval = evaluation?.requiresApproval ?? false;

    state = state.copyWith(submitting: true, clearError: true);
    try {
      await ref
          .read(giftControllerProvider)
          .recordGift(
            itemType: state.itemType,
            productId: state.productId,
            quantity: state.quantity!,
            reason: state.reason.trim(),
            ownerEmail: needsApproval ? state.ownerEmail.trim() : null,
            ownerPin: needsApproval ? state.ownerPin : null,
          );
      state = const RecordGiftFormState(justRecorded: true);
    } on NoShiftOpenException {
      state = state.copyWith(
        submitting: false,
        errorMessage: 'No shift is currently open — a gift needs one.',
      );
    } on InvalidCredentialsException {
      state = state.copyWith(
        submitting: false,
        ownerPin: '',
        errorMessage: 'Incorrect owner email or PIN.',
      );
    } on PinLockedException catch (e) {
      final seconds = e.lockedUntil
          .difference(DateTime.now())
          .inSeconds
          .clamp(1, 999);
      state = state.copyWith(
        submitting: false,
        ownerPin: '',
        errorMessage: 'Too many attempts. Try again in ${seconds}s.',
      );
    } on NotAnActiveOwnerException {
      state = state.copyWith(
        submitting: false,
        ownerPin: '',
        errorMessage: 'That person is not currently an active owner.',
      );
    } on DeviceVerificationRequiredException {
      state = state.copyWith(
        submitting: false,
        ownerPin: '',
        errorMessage: "That owner hasn't verified this device yet.",
      );
    } catch (_) {
      state = state.copyWith(
        submitting: false,
        errorMessage: 'Could not record that gift. Try again.',
      );
    }
  }
}

final recordGiftControllerProvider =
    StateNotifierProvider.autoDispose<
      RecordGiftController,
      RecordGiftFormState
    >((ref) => RecordGiftController(ref));
