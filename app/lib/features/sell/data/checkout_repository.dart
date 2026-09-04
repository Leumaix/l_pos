import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/business_config.dart';
import '../../auth/data/firebase_auth_repository.dart';
import '../../customers/data/customer_repository.dart';
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
  /// decrement, and — for a customer-account sale — the customer's
  /// credit-sale balance and an accurate transaction-ledger entry.
  /// All-or-nothing.
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

  FakeCheckoutRepository({required this._inventory, required this._customers, required this._sales});

  int _idCounter = 0;

  @override
  String newSaleId() => 'sale-fake-${_idCounter++}';

  @override
  Future<void> commitSale({required Sale sale, required int gasUnitsDeducted}) async {
    if (gasUnitsDeducted > 0) {
      await _inventory.deductGasStock(gasUnitsDeducted, staffId: sale.staffId, staffName: sale.staffName);
    }

    for (final line in sale.items.whereType<ProductCartLine>()) {
      await _inventory.decrementProductStock(line.product.id, line.quantity);
    }

    if (sale.method == PaymentMethod.customerAccount) {
      await _customers.recordCreditSale(
        customerId: sale.customerId!,
        amountNaira: sale.total,
        saleId: sale.id,
      );
    }

    await _sales.recordSale(sale);
  }
}

/// Real implementation — one Firestore runTransaction covering every
/// write a checkout implies. A transaction (not a WriteBatch) because
/// the customer-account branch needs the same accurate-balanceAfter
/// guarantee as FirebaseCustomerRepository: read the current balance,
/// compute the true new one, write both atomically, with Firestore's
/// automatic conflict retry closing the race window a blind increment
/// would leave open. All Firestore reads must happen before any writes
/// within one transaction, so the (single, optional) customer-balance
/// read happens first.
class FirebaseCheckoutRepository implements CheckoutRepository {
  final FirebaseAuthRepository _firebaseAuth;

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

  @override
  String newSaleId() => _salesCollection.doc().id;

  @override
  Future<void> commitSale({required Sale sale, required int gasUnitsDeducted}) async {
    final isCreditSale = sale.method == PaymentMethod.customerAccount;
    final customerRef = isCreditSale ? _customersCollection.doc(sale.customerId!) : null;
    // Minted up front (synchronous — .doc() with no args just generates
    // an id) so the customer update below can reference it via
    // lastTransactionId; firestore.rules requires that pairing for any
    // staff-performed balance change. See FirebaseCustomerRepository's
    // matching pattern and the rule's own doc comment for why.
    final customerTxRef = customerRef?.collection('transactions').doc();

    await _firestore.runTransaction((transaction) async {
      // All reads first — a Firestore transaction requires it.
      int? newCustomerBalance;
      if (customerRef != null) {
        final customerSnapshot = await transaction.get(customerRef);
        final currentBalance = (customerSnapshot.data()?['balance'] as num? ?? 0).toInt();
        newCustomerBalance = currentBalance + sale.total;
      }

      transaction.set(_salesCollection.doc(sale.id), FirebaseSalesRepository.saleToDoc(sale));

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
          'amountNaira': sale.total,
          'balanceAfter': newCustomerBalance,
          'createdAt': FieldValue.serverTimestamp(),
          'saleId': sale.id,
        });
      }
    });
  }
}
