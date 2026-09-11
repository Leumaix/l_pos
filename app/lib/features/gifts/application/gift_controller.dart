import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../auth/application/auth_providers.dart';
import '../../sell/application/inventory_providers.dart';
import '../../shift/application/shift_providers.dart';
import '../../shift/data/shift_repository.dart';
import '../domain/gift.dart';
import 'gift_providers.dart';

/// The default thresholds above which a gift needs the owner's own PIN,
/// entered on the device at the moment of gifting (no push-notification
/// infrastructure exists to approve remotely) — gas is a pure quantity
/// check, product a value check. Both are re-derived and enforced again
/// server-side (see firestore.rules) — this is the client-side mirror
/// for a clean UI decision, never trusted alone for the actual commit.
const kGasGiftApprovalThresholdKg = 2;
const kProductGiftApprovalThresholdNaira = 2000;

/// What [GiftController.evaluateGift] resolves before anything is
/// committed — whether the owner-approval step is needed, and the
/// estimated value that decision (and Reports) are based on.
class GiftEvaluation {
  final bool requiresApproval;
  final int estimatedValueNaira;

  const GiftEvaluation({required this.requiresApproval, required this.estimatedValueNaira});
}

/// Thrown by [GiftController.recordGift] when [GiftEvaluation.requiresApproval]
/// was true but no owner email/PIN was supplied — a programmer-error
/// guard (the UI is responsible for calling [GiftController.evaluateGift]
/// first and showing the approval step before ever reaching this), not a
/// normal-flow error path. Mirrors ShiftRequiredForCashExpenseException's
/// own reasoning in the expenses feature.
class OwnerApprovalRequiredException implements Exception {
  const OwnerApprovalRequiredException();
}

/// Any active staff member — not owner-only. Mirrors
/// ExpenseController.recordExpense's shape closely, with two
/// differences: every gift needs an open shift unconditionally (gifting
/// removes real stock the same way a sale does), and an over-threshold
/// gift needs a genuine owner-PIN approval exchange first (see
/// AuthRepository.verifyActiveOwnerPin/firestoreForEmail and
/// GiftRepository.recordOwnerApproval's own doc comments for the full
/// mechanism).
class GiftController {
  final Ref ref;

  GiftController(this.ref);

  /// Pure-ish threshold decision (reads the current gas rate / product
  /// catalog, but commits nothing) — call this FIRST, before ever
  /// prompting for an owner PIN, so the fast path (an under-threshold
  /// gift) never shows an approval step at all. [recordGift] re-derives
  /// this same decision itself rather than trusting a stale evaluation
  /// passed back in.
  GiftEvaluation evaluateGift({required GiftItemType itemType, String? productId, required num quantity}) {
    if (itemType == GiftItemType.gas) {
      final rate = ref.read(gasRateProvider);
      return GiftEvaluation(
        requiresApproval: quantity > kGasGiftApprovalThresholdKg,
        estimatedValueNaira: unitsForKg(quantity, rate),
      );
    }
    final product = ref.read(inventoryRepositoryProvider).currentProducts.firstWhere((p) => p.id == productId);
    final estimatedValueNaira = product.price * quantity.round();
    return GiftEvaluation(
      requiresApproval: estimatedValueNaira > kProductGiftApprovalThresholdNaira,
      estimatedValueNaira: estimatedValueNaira,
    );
  }

  Future<Gift> recordGift({
    required GiftItemType itemType,
    String? productId,
    required num quantity,
    required String reason,
    String? ownerEmail,
    String? ownerPin,
  }) async {
    final staff = ref.read(authStateProvider).valueOrNull;
    if (staff == null) {
      throw StateError('recordGift called with no signed-in staff member');
    }

    // fetchCurrentShift — the one-shot authoritative read, not the
    // cached currentShift getter — same reasoning ExpenseController
    // already established: this screen is reached from Home directly,
    // not primed by Sell.
    final shift = await ref.read(shiftRepositoryProvider).fetchCurrentShift();
    if (shift == null) throw const NoShiftOpenException();

    final evaluation = evaluateGift(itemType: itemType, productId: productId, quantity: quantity);

    final gifts = ref.read(giftRepositoryProvider);
    final giftId = gifts.newGiftId();

    String? approvedByOwnerUid;
    if (evaluation.requiresApproval) {
      if (ownerEmail == null || ownerPin == null) {
        throw const OwnerApprovalRequiredException();
      }
      final auth = ref.read(authRepositoryProvider);
      final ownerUid = await auth.verifyActiveOwnerPin(email: ownerEmail, pin: ownerPin);
      await gifts.recordOwnerApproval(giftId: giftId, ownerEmail: ownerEmail, ownerUid: ownerUid);
      approvedByOwnerUid = ownerUid;
    }

    final gift = buildGift(
      itemType: itemType,
      productId: productId,
      quantity: quantity,
      estimatedValueNaira: evaluation.estimatedValueNaira,
      reason: reason,
      staffId: staff.uid,
      staffName: staff.name,
      id: giftId,
      shiftId: shift.plannedHistoryId,
      requiresApproval: evaluation.requiresApproval,
      approvedByOwnerUid: approvedByOwnerUid,
      createdAt: DateTime.now(),
    );

    int? gasUnitsDeducted;
    if (itemType == GiftItemType.gas) {
      final stock = ref.read(inventoryRepositoryProvider).currentGasStock;
      final rate = ref.read(gasRateProvider);
      gasUnitsDeducted = sellByKg(stock, quantity, rate).unitsDeducted;
    }

    await gifts.commitGift(gift: gift, gasUnitsDeducted: gasUnitsDeducted);
    return gift;
  }
}

final giftControllerProvider = Provider((ref) => GiftController(ref));
