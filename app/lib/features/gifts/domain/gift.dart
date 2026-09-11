/// Gas or a catalog product. Deliberately NOT reusing sell's CartLine
/// hierarchy — a gift is a single item, never a cart, and carries fields
/// (reason, approval) a sale line never needs.
enum GiftItemType { gas, product }

/// A single gift of gas or a product — real stock leaving with zero
/// revenue, staff-attributed, reason required. Mirrors Expense's shape
/// (sell/../expenses/domain/expense.dart) closely, with two differences:
/// [shiftId] is ALWAYS required (gifting removes real stock the same way
/// a sale does, unlike a non-cash expense), and the [requiresApproval]/
/// [approvedByOwnerUid] pair, present only when the gift crossed the
/// value/quantity threshold — see GiftController for how that owner
/// approval is actually obtained.
class Gift {
  final String id;
  final GiftItemType itemType;

  /// Required when [itemType] is product; null for gas.
  final String? productId;

  /// Kg for gas, unit count for a product.
  final num quantity;

  /// Reports-only — no revenue is ever recognized for a gift. For gas,
  /// computed client-side as quantity * the current gas rate (same
  /// trust boundary as sale.total never being cross-checked against
  /// cart contents — see checkout.dart). For a product, this is what
  /// firestore.rules cross-checks against the product's own real price
  /// (see that rule's own comment) — it's also what the approval
  /// threshold is judged against for products.
  final int estimatedValueNaira;

  final String reason;
  final String staffId;
  final String staffName;

  /// The currently open shift's stable id (OpenShift.plannedHistoryId) —
  /// same reuse expense-tracking already established. Unlike an expense,
  /// this is required unconditionally: every gift removes real stock,
  /// the same way a sale does.
  final String shiftId;

  final bool requiresApproval;

  /// Set only when [requiresApproval] is true — the owner's uid, proven
  /// by GiftController's owner-PIN-approval flow, not merely claimed.
  final String? approvedByOwnerUid;

  final DateTime createdAt;

  const Gift({
    required this.id,
    required this.itemType,
    this.productId,
    required this.quantity,
    required this.estimatedValueNaira,
    required this.reason,
    required this.staffId,
    required this.staffName,
    required this.shiftId,
    required this.requiresApproval,
    this.approvedByOwnerUid,
    required this.createdAt,
  });
}

/// Thrown when [buildGift] is given a zero or negative quantity.
class InvalidGiftQuantityException implements Exception {
  final num quantity;
  const InvalidGiftQuantityException(this.quantity);
}

/// Thrown when [Gift.reason] is missing or blank — every gift needs a
/// real, human-written reason, no exceptions.
class GiftReasonRequiredException implements Exception {
  const GiftReasonRequiredException();
}

/// Thrown when [GiftItemType.product] is given with no [Gift.productId].
class ProductRequiredForGiftException implements Exception {
  const ProductRequiredForGiftException();
}

/// Pure: validates and constructs the [Gift] record. Mirrors
/// buildExpense's shape (expenses/domain/expense.dart) — never mutates
/// anything; the caller (GiftController/GiftRepository) handles the
/// actual stock-deduction commit and, when required, the owner-approval
/// exchange, both BEFORE this is called — [requiresApproval]/
/// [approvedByOwnerUid] are passed in already resolved, not computed
/// here (the threshold decision needs the current gas rate/product price,
/// which this pure function deliberately has no access to).
Gift buildGift({
  required GiftItemType itemType,
  String? productId,
  required num quantity,
  required int estimatedValueNaira,
  required String reason,
  required String staffId,
  required String staffName,
  required String id,
  required String shiftId,
  required bool requiresApproval,
  String? approvedByOwnerUid,
  required DateTime createdAt,
}) {
  if (quantity <= 0) throw InvalidGiftQuantityException(quantity);
  if (reason.trim().isEmpty) throw const GiftReasonRequiredException();
  if (itemType == GiftItemType.product && productId == null) {
    throw const ProductRequiredForGiftException();
  }

  return Gift(
    id: id,
    itemType: itemType,
    productId: productId,
    quantity: quantity,
    estimatedValueNaira: estimatedValueNaira,
    reason: reason,
    staffId: staffId,
    staffName: staffName,
    shiftId: shiftId,
    requiresApproval: requiresApproval,
    approvedByOwnerUid: approvedByOwnerUid,
    createdAt: createdAt,
  );
}
