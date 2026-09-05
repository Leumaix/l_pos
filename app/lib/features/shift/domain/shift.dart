/// A business day's cash-drawer tracking. Scoped to the whole business —
/// opened once in the morning, closed once at night, regardless of how
/// many staff members hand the shared tablet off to each other via the
/// existing multi-staff mechanism in between (no shift action happens at
/// a handoff — see FirebaseAuthRepository's per-device staff switching).
///
/// [openingFloatNaira] is the starting cash declared at open. The running
/// per-method totals are accumulated atomically, one sale at a time,
/// inside the checkout transaction itself (see
/// FirebaseCheckoutRepository.commitSale) — never queried from /sales at
/// close time, partly for cost but mainly because /sales is owner-read-
/// only and any staff member must be able to close a shift.
class OpenShift {
  final int openingFloatNaira;
  final String openedByStaffId;
  final String openedByStaffName;
  final DateTime openedAt;
  final int cashTotalNaira;
  final int cardTotalNaira;
  final int transferTotalNaira;
  final int creditTotalNaira;
  final int salesCount;

  const OpenShift({
    required this.openingFloatNaira,
    required this.openedByStaffId,
    required this.openedByStaffName,
    required this.openedAt,
    required this.cashTotalNaira,
    required this.cardTotalNaira,
    required this.transferTotalNaira,
    required this.creditTotalNaira,
    required this.salesCount,
  });

  /// The physical cash a correct drawer count should show — only cash
  /// sales add real cash to the drawer; card/transfer/credit sales move
  /// money elsewhere (a terminal, a bank transfer, a customer's running
  /// balance), never into this drawer.
  int get expectedCashNaira => openingFloatNaira + cashTotalNaira;
}

/// An immutable, archived record of a closed shift — never edited after
/// the fact; a correction is a note for the next shift, not a rewrite of
/// history (same append-only discipline as gasStockLedger/customer
/// transactions).
class ClosedShift extends OpenShift {
  final int countedCashNaira;
  final int varianceNaira;
  final String closedByStaffId;
  final String closedByStaffName;
  final DateTime closedAt;

  const ClosedShift({
    required super.openingFloatNaira,
    required super.openedByStaffId,
    required super.openedByStaffName,
    required super.openedAt,
    required super.cashTotalNaira,
    required super.cardTotalNaira,
    required super.transferTotalNaira,
    required super.creditTotalNaira,
    required super.salesCount,
    required this.countedCashNaira,
    required this.varianceNaira,
    required this.closedByStaffId,
    required this.closedByStaffName,
    required this.closedAt,
  });
}

/// Closes [shift]: counts [countedCashNaira] against what the shift's own
/// running totals say the drawer should hold, and records the variance.
/// Pure — the caller is responsible for actually archiving/deleting the
/// Firestore-side state; this just computes the numbers that go in that
/// archive.
ClosedShift closeShift(
  OpenShift shift, {
  required int countedCashNaira,
  required String staffId,
  required String staffName,
  required DateTime closedAt,
}) {
  final expected = shift.expectedCashNaira;
  return ClosedShift(
    openingFloatNaira: shift.openingFloatNaira,
    openedByStaffId: shift.openedByStaffId,
    openedByStaffName: shift.openedByStaffName,
    openedAt: shift.openedAt,
    cashTotalNaira: shift.cashTotalNaira,
    cardTotalNaira: shift.cardTotalNaira,
    transferTotalNaira: shift.transferTotalNaira,
    creditTotalNaira: shift.creditTotalNaira,
    salesCount: shift.salesCount,
    countedCashNaira: countedCashNaira,
    varianceNaira: countedCashNaira - expected,
    closedByStaffId: staffId,
    closedByStaffName: staffName,
    closedAt: closedAt,
  );
}
