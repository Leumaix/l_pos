import 'dart:async';

import '../../sell/domain/sale.dart' show PaymentMethod;
import '../domain/shift.dart';

/// Thrown by anything that requires an open shift (checkout, opening a
/// new one) when none exists. firestore.rules independently enforces the
/// same boundary server-side (exists(shiftState/current) on /sales
/// create, create-only semantics on shiftState/current itself) — this is
/// the clean client-side error, not the real enforcement.
class NoShiftOpenException implements Exception {
  const NoShiftOpenException();
}

/// Thrown by [ShiftRepository.openDay] when a shift is already open.
/// Structurally impossible to hit via the real UI (Home only shows the
/// Open Day action when [ShiftRepository.currentShift] is null), but a
/// real, named failure mode for the same "don't assume, the write can
/// still race" reasons every other repository in this app names its
/// exceptions rather than letting a raw Firestore error surface.
class ShiftAlreadyOpenException implements Exception {
  const ShiftAlreadyOpenException();
}

abstract class ShiftRepository {
  Stream<OpenShift?> watchCurrentShift();

  /// Synchronous access to the current shift (null if none is open) —
  /// same "don't wait on the stream" contract as
  /// InventoryRepository.currentGasStock, used by the router's redirect
  /// and CheckoutController's guard.
  OpenShift? get currentShift;

  /// A one-shot, authoritative read of the current shift — NOT
  /// [currentShift], which is a lazily-started, cached getter that can
  /// still be showing its cold-start default (null) the very first time
  /// it's ever accessed in a given app session, e.g. reaching Close Day
  /// directly from Home without ever visiting Sell first (which is what
  /// normally primes it via the router's redirect). Close Day's preview
  /// needs to be right the first time it's shown, not just eventually
  /// consistent — see CloseDayController.preparePreview.
  Future<OpenShift?> fetchCurrentShift();

  Future<void> openDay({required int openingFloatNaira, required String staffId, required String staffName});

  /// Reads the current shift, computes the close via [closeShift], and
  /// archives it — the real (Firestore) implementation does this as one
  /// runTransaction, deleting shiftState/current and creating the
  /// shiftHistory record atomically. Throws [NoShiftOpenException] if
  /// nothing is open.
  Future<ClosedShift> closeDay({
    required int countedCashNaira,
    required String staffId,
    required String staffName,
  });

  /// Owner-only at the rules level — for Reports' shift history.
  Stream<List<ClosedShift>> watchShiftHistory();
}

/// In-memory stand-in. Defaults to a shift already open (a reasonable
/// starting float, no sales yet) rather than closed — most existing
/// tests/dev flows (Sell, Payment, Restock) care about everything BUT
/// shift-gating and would otherwise all need to remember to open one
/// first. Tests that specifically exercise shift-gating construct this
/// with `openShift: false` or call closeDay() themselves.
class FakeShiftRepository implements ShiftRepository {
  OpenShift? _current;
  final _controller = StreamController<OpenShift?>.broadcast();
  final List<ClosedShift> _history = [];
  final _historyController = StreamController<List<ClosedShift>>.broadcast();

  FakeShiftRepository({bool openShift = true})
    : _current = openShift
          ? OpenShift(
              openingFloatNaira: 10000,
              openedByStaffId: 'seed-owner',
              openedByStaffName: 'Chidi (Owner)',
              openedAt: DateTime(2026, 1, 1, 8),
              cashTotalNaira: 0,
              cardTotalNaira: 0,
              transferTotalNaira: 0,
              creditTotalNaira: 0,
              salesCount: 0,
            )
          : null;

  @override
  OpenShift? get currentShift => _current;

  @override
  Future<OpenShift?> fetchCurrentShift() async => _current;

  @override
  Stream<OpenShift?> watchCurrentShift() {
    return Stream.multi((controller) {
      controller.add(_current);
      final subscription = _controller.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<void> openDay({required int openingFloatNaira, required String staffId, required String staffName}) async {
    if (_current != null) throw const ShiftAlreadyOpenException();
    _current = OpenShift(
      openingFloatNaira: openingFloatNaira,
      openedByStaffId: staffId,
      openedByStaffName: staffName,
      openedAt: DateTime.now(),
      cashTotalNaira: 0,
      cardTotalNaira: 0,
      transferTotalNaira: 0,
      creditTotalNaira: 0,
      salesCount: 0,
    );
    _controller.add(_current);
  }

  @override
  Future<ClosedShift> closeDay({
    required int countedCashNaira,
    required String staffId,
    required String staffName,
  }) async {
    final shift = _current;
    if (shift == null) throw const NoShiftOpenException();
    final closed = closeShift(
      shift,
      countedCashNaira: countedCashNaira,
      staffId: staffId,
      staffName: staffName,
      closedAt: DateTime.now(),
    );
    _current = null;
    _history.insert(0, closed);
    _controller.add(null);
    _historyController.add(List.unmodifiable(_history));
    return closed;
  }

  @override
  Stream<List<ClosedShift>> watchShiftHistory() {
    return Stream.multi((controller) {
      controller.add(List.unmodifiable(_history));
      final subscription = _historyController.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  /// Test-only: applies a sale's totals the same way the real checkout
  /// transaction would, without going through a full FakeCheckoutRepository
  /// wiring. Throws [NoShiftOpenException] if nothing is open — mirrors
  /// the real guard FirebaseCheckoutRepository.commitSale performs. Not
  /// part of [ShiftRepository]'s interface: the real equivalent isn't a
  /// standalone repository method either — it's inlined directly into
  /// FirebaseCheckoutRepository's own transaction (see its doc comment),
  /// so FakeCheckoutRepository reaches in here the same way.
  void debugApplySaleTotals({required PaymentMethod method, required int amountNaira}) {
    final shift = _current;
    if (shift == null) throw const NoShiftOpenException();
    _current = OpenShift(
      openingFloatNaira: shift.openingFloatNaira,
      openedByStaffId: shift.openedByStaffId,
      openedByStaffName: shift.openedByStaffName,
      openedAt: shift.openedAt,
      cashTotalNaira: shift.cashTotalNaira + (method == PaymentMethod.cash ? amountNaira : 0),
      cardTotalNaira: shift.cardTotalNaira + (method == PaymentMethod.card ? amountNaira : 0),
      transferTotalNaira: shift.transferTotalNaira + (method == PaymentMethod.transfer ? amountNaira : 0),
      creditTotalNaira: shift.creditTotalNaira + (method == PaymentMethod.customerAccount ? amountNaira : 0),
      salesCount: shift.salesCount + 1,
    );
    _controller.add(_current);
  }
}
