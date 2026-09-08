import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/business_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../customers/data/customer_repository.dart';
import '../../shift/data/shift_repository.dart';
import '../domain/cart_line.dart';
import '../domain/sale.dart';
import 'firebase_sales_repository.dart';
import 'inventory_repository.dart';
import 'sales_repository.dart';

/// The atomic commit step of a checkout — the one place stock, a
/// customer's credit balance, and the sales log actually change
/// together. A completed sale must never be observable half-done (stock
/// moved but no sale record, or vice versa); see CheckoutController,
/// which is the only caller.
///
/// A standalone repository rather than a method on Sales/Inventory/
/// Customer: this is a genuinely cross-cutting concern that doesn't
/// belong to any one of their bounded concerns (gas/products belong to
/// InventoryRepository, a customer's balance to CustomerRepository, the
/// sale record to SalesRepository) — same one-repository-per-concern
/// convention as everywhere else in this app, rather than blurring
/// ownership by having one repository reach into another's collections.
abstract class CheckoutRepository {
  /// A fresh, globally-unique sale id, minted before the [Sale] itself is
  /// built (buildSale needs an id up front to construct the record).
  String newSaleId();

  /// Commits every mutation a completed checkout implies as one atomic
  /// write: the sale record, gas stock + its ledger entry (if
  /// [gasUnitsDeducted] is nonzero), each sold product's stockCount
  /// decrement, the current shift's running per-method total (see the
  /// shift feature's ShiftRepository/OpenShift), and — for a customer-
  /// account sale — the customer's credit-sale balance and an accurate
  /// transaction-ledger entry. All-or-nothing.
  ///
  /// Throws [NoShiftOpenException] if no shift is currently open — a
  /// sale can never be recorded outside an open business day. This is a
  /// clean client-side error for a clear message; firestore.rules
  /// independently enforces the same boundary server-side
  /// (exists(shiftState/current) on /sales create), so this can't
  /// actually be bypassed even if this check were somehow skipped.
  Future<void> commitSale({required Sale sale, required int gasUnitsDeducted});
}

/// In-memory stand-in — delegates to the three fakes it's handed,
/// replaying today's sequential-calls behavior. Already effectively
/// atomic in this single-threaded fake (no await boundary anything else
/// could interleave through), same reasoning CheckoutController's old
/// doc comment gave before the real transaction existed.
class FakeCheckoutRepository implements CheckoutRepository {
  final InventoryRepository _inventory;
  final CustomerRepository _customers;
  final SalesRepository _sales;
  // Concrete FakeShiftRepository, not the abstract ShiftRepository — this
  // needs debugApplySaleTotals, which is fake-only test plumbing (the
  // real equivalent is inlined directly into
  // FirebaseCheckoutRepository's own transaction, not a standalone
  // ShiftRepository method at all). Fine here: FakeCheckoutRepository is
  // itself test-only, never meant to be swapped for the real thing.
  final FakeShiftRepository _shift;

  // Defaults to an already-open shift — most existing tests/dev flows
  // care about Sell/Payment/Restock, not shift-gating specifically, and
  // would otherwise all need to remember to open one first. Tests that
  // specifically exercise shift-gating pass a closed FakeShiftRepository.
  FakeCheckoutRepository({
    required this._inventory,
    required this._customers,
    required this._sales,
    FakeShiftRepository? shift,
  }) : _shift = shift ?? FakeShiftRepository();

  int _idCounter = 0;

  @override
  String newSaleId() => 'sale-fake-${_idCounter++}';

  @override
  Future<void> commitSale({required Sale sale, required int gasUnitsDeducted}) async {
    // Mirrors FirebaseCheckoutRepository.commitSale's guard — see its
    // doc comment for why this same check exists twice (client-side
    // clarity here, firestore.rules for the real enforcement there).
    if (_shift.currentShift == null) throw const NoShiftOpenException();

    if (gasUnitsDeducted > 0) {
      await _inventory.deductGasStock(gasUnitsDeducted, staffId: sale.staffId, staffName: sale.staffName);
    }

    for (final line in sale.items.whereType<ProductCartLine>()) {
      await _inventory.decrementProductStock(line.product.id, line.quantity);
    }

    final creditLine = sale.customerAccountLine;
    if (creditLine != null) {
      await _customers.recordCreditSale(
        customerId: creditLine.customerId!,
        amountNaira: creditLine.amountNaira,
        saleId: sale.id,
      );
    }

    await _sales.recordSale(sale);
    // Once per payment line — not once per sale — so a split correctly
    // touches every method it used, and a negative cash line (change
    // given, on any method) nets against cashTotalNaira exactly like the
    // real FirebaseCheckoutRepository's grouped increment below.
    for (final line in sale.payments) {
      _shift.debugApplySaleTotals(method: line.method, amountNaira: line.amountNaira);
    }
  }
}

/// Real implementation — one Firestore runTransaction covering every
/// write a checkout implies. A transaction (not a WriteBatch) because
/// the customer-account branch needs the same accurate-balanceAfter
/// guarantee as FirebaseCustomerRepository: read the current balance,
/// compute the true new one, write both atomically, with Firestore's
/// automatic conflict retry closing the race window a blind increment
/// would leave open. It's also why the shift-open check has to live
/// HERE rather than only at the router/CheckoutController level: a
/// transaction can still fail firestore.rules' own exists() check even
/// if the client's own earlier check passed (someone closed the shift on
/// a second device in the gap between). All Firestore reads must happen
/// before any writes within one transaction, so the (single, optional)
/// customer-balance read and the shift-state read both happen first.
class FirebaseCheckoutRepository implements CheckoutRepository {
  final AuthRepository _firebaseAuth;

  FirebaseCheckoutRepository(this._firebaseAuth);

  FirebaseFirestore get _firestore {
    final firestore = _firebaseAuth.activeFirestore;
    if (firestore == null) {
      throw StateError('CheckoutRepository used with nobody currently signed in.');
    }
    return firestore;
  }

  CollectionReference<Map<String, dynamic>> get _salesCollection =>
      _firestore.collection('businesses/$kBusinessId/sales');

  DocumentReference<Map<String, dynamic>> get _gasStockDoc =>
      _firestore.doc('businesses/$kBusinessId/gasStock/current');

  CollectionReference<Map<String, dynamic>> get _gasStockLedgerCollection =>
      _firestore.collection('businesses/$kBusinessId/gasStockLedger');

  CollectionReference<Map<String, dynamic>> get _productsCollection =>
      _firestore.collection('businesses/$kBusinessId/products');

  CollectionReference<Map<String, dynamic>> get _customersCollection =>
      _firestore.collection('businesses/$kBusinessId/customers');

  DocumentReference<Map<String, dynamic>> get _shiftStateDoc =>
      _firestore.doc('businesses/$kBusinessId/shiftState/current');

  static const _shiftTotalFieldByMethod = {
    PaymentMethod.cash: 'cashTotalNaira',
    PaymentMethod.card: 'cardTotalNaira',
    PaymentMethod.transfer: 'transferTotalNaira',
    PaymentMethod.customerAccount: 'creditTotalNaira',
  };

  @override
  String newSaleId() => _salesCollection.doc().id;

  @override
  Future<void> commitSale({required Sale sale, required int gasUnitsDeducted}) async {
    final creditLine = sale.customerAccountLine;
    final customerRef = creditLine != null ? _customersCollection.doc(creditLine.customerId!) : null;
    // Minted up front (synchronous — .doc() with no args just generates
    // an id) so the customer update below can reference it via
    // lastTransactionId; firestore.rules requires that pairing for any
    // staff-performed balance change. See FirebaseCustomerRepository's
    // matching pattern and the rule's own doc comment for why.
    final customerTxRef = customerRef?.collection('transactions').doc();

    await _firestore.runTransaction((transaction) async {
      // All reads first — a Firestore transaction requires it.
      final shiftSnapshot = await transaction.get(_shiftStateDoc);
      if (!shiftSnapshot.exists) throw const NoShiftOpenException();

      int? newCustomerBalance;
      if (customerRef != null) {
        final customerSnapshot = await transaction.get(customerRef);
        final currentBalance = (customerSnapshot.data()?['balance'] as num? ?? 0).toInt();
        newCustomerBalance = currentBalance + creditLine!.amountNaira;
      }

      transaction.set(_salesCollection.doc(sale.id), FirebaseSalesRepository.saleToDoc(sale));

      // The shift's running per-method totals — see shiftState/current's
      // update rule in firestore.rules, scoped to exactly these fields.
      // Grouped by method first (not one increment call per payment
      // line): a Firestore update() can only touch a given field once,
      // so a split sale with two lines on the same method (e.g. a cash
      // payment plus a separate cash change line) has to net out into a
      // single increment amount per field before this map is built.
      final totalsByMethod = <PaymentMethod, int>{};
      for (final line in sale.payments) {
        totalsByMethod[line.method] = (totalsByMethod[line.method] ?? 0) + line.amountNaira;
      }
      transaction.update(_shiftStateDoc, {
        'salesCount': FieldValue.increment(1),
        // Lets firestore.rules verify this update is paired with THIS
        // exact sale — same pairing pattern lastTransactionId already
        // uses on customers/{customerId} — so the totals increment can
        // be cross-checked against what sale.payments actually says,
        // not just trusted. See that rule's own comment for the fraud
        // vector this closes.
        'lastSaleId': sale.id,
        for (final entry in totalsByMethod.entries) _shiftTotalFieldByMethod[entry.key]!: FieldValue.increment(entry.value),
      });

      if (gasUnitsDeducted != 0) {
        transaction.set(_gasStockDoc, {'units': FieldValue.increment(-gasUnitsDeducted)}, SetOptions(merge: true));
        transaction.set(_gasStockLedgerCollection.doc(), {
          'type': 'sale',
          'unitsDelta': -gasUnitsDeducted,
          'staffId': sale.staffId,
          'staffName': sale.staffName,
          'saleId': sale.id,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      for (final line in sale.items.whereType<ProductCartLine>()) {
        // Server-side oversell guard lives in firestore.rules
        // (stockCount >= 0 on the resulting write) — a blind increment
        // here, rejected by the rule if it would go negative.
        transaction.update(_productsCollection.doc(line.product.id), {
          'stockCount': FieldValue.increment(-line.quantity),
        });
      }

      if (customerRef != null) {
        transaction.update(customerRef, {'balance': newCustomerBalance, 'lastTransactionId': customerTxRef!.id});
        transaction.set(customerTxRef, {
          'type': 'creditSale',
          // The customerAccount line's own amount — not sale.total, which
          // may be larger on a split sale where only PART of the total was
          // charged to this customer's account.
          'amountNaira': creditLine!.amountNaira,
          'balanceAfter': newCustomerBalance,
          'createdAt': FieldValue.serverTimestamp(),
          'saleId': sale.id,
        });
      }
    });
  }
}
