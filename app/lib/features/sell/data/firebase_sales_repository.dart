import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/business_config.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/sale.dart';
import 'cart_line_firestore_codec.dart';
import 'sales_repository.dart';

/// Real implementation — reads/writes through whoever is CURRENTLY
/// ACTIVE's authenticated Firestore session (see
/// FirebaseAuthRepository.activeFirestore), same pattern as every other
/// Firebase-backed repository in this app. Read access is owner-only at
/// the rules level (revenue is business-wide financial data an attendant
/// isn't shown, by design — see Home's owner/attendant split); this
/// class doesn't itself enforce that, it just reflects what the rules
/// already allow or deny.
class FirebaseSalesRepository implements SalesRepository {
  final AuthRepository _firebaseAuth;

  FirebaseSalesRepository(this._firebaseAuth);

  FirebaseFirestore get _firestore {
    final firestore = _firebaseAuth.activeFirestore;
    if (firestore == null) {
      throw StateError('SalesRepository used with nobody currently signed in.');
    }
    return firestore;
  }

  CollectionReference<Map<String, dynamic>> get _salesCollection =>
      _firestore.collection('businesses/$kBusinessId/sales');

  /// Public — reused by FirebaseCheckoutRepository, which writes a sale
  /// doc as part of its own atomic transaction rather than delegating to
  /// recordSale (a checkout commit needs everything in ONE transaction,
  /// not a separate write this class would issue on its own).
  ///
  /// Every sale written from here on is payments-shaped — there is no
  /// path that still writes the old method/cashGiven/changeGiven/
  /// customerId fields. See [_saleFromDoc] for how an old-shaped doc
  /// already sitting in Firestore is still read correctly, with no
  /// migration ever needed.
  static Map<String, dynamic> saleToDoc(Sale sale) => {
    'receiptNumber': sale.receiptNumber,
    'items': sale.items.map(cartLineToMap).toList(),
    'subtotal': sale.subtotal,
    'total': sale.total,
    'payments': sale.payments.map(_paymentLineToMap).toList(),
    'staffId': sale.staffId,
    'staffName': sale.staffName,
    'createdAt': Timestamp.fromDate(sale.createdAt),
  };

  static Map<String, dynamic> _paymentLineToMap(PaymentLine line) => {
    'method': line.method.name,
    'amountNaira': line.amountNaira,
    'customerId': line.customerId,
    'customerName': line.customerName,
  };

  static PaymentLine _paymentLineFromMap(Map<String, dynamic> map) => PaymentLine(
    method: PaymentMethod.values.byName(map['method'] as String),
    amountNaira: (map['amountNaira'] as num).toInt(),
    customerId: map['customerId'] as String?,
    customerName: map['customerName'] as String?,
  );

  static Sale _saleFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Sale(
      id: doc.id,
      receiptNumber: data['receiptNumber'] as String,
      items: (data['items'] as List<dynamic>)
          .map((raw) => cartLineFromMap(raw as Map<String, dynamic>))
          .toList(),
      subtotal: (data['subtotal'] as num).toInt(),
      total: (data['total'] as num).toInt(),
      payments: _paymentsFromDoc(data),
      staffId: data['staffId'] as String,
      staffName: data['staffName'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  /// Reads [Sale.payments] out of a Firestore doc — presence of the
  /// `payments` field (vs. the old `method`/`cashGiven`/`changeGiven`/
  /// `customerId` fields) is what distinguishes a new-shaped doc from a
  /// pre-migration one, not a version number. An old doc is translated
  /// PURELY IN MEMORY, every time it's read — this method never writes
  /// anything back, so there is no migration step, no risk of a script
  /// mishandling real financial history, and old shiftHistory/shiftState
  /// numbers (already computed correctly for the single-method case they
  /// actually saw) need no reinterpretation either.
  static List<PaymentLine> _paymentsFromDoc(Map<String, dynamic> data) {
    final rawPayments = data['payments'] as List<dynamic>?;
    if (rawPayments != null) {
      return rawPayments
          .map((raw) => _paymentLineFromMap(raw as Map<String, dynamic>))
          .toList();
    }

    // Old-shaped doc. Same cash-with-change mapping
    // CheckoutController._paymentsFor uses for a freshly-built sale — a
    // sale recorded before this migration and one built today from the
    // same real-world inputs produce byte-for-byte identical payments.
    final method = PaymentMethod.values.byName(data['method'] as String);
    final total = (data['total'] as num).toInt();
    switch (method) {
      case PaymentMethod.cash:
        final cashGiven = (data['cashGiven'] as num?)?.toInt() ?? total;
        final changeGiven = (data['changeGiven'] as num?)?.toInt() ?? 0;
        return [
          PaymentLine(method: PaymentMethod.cash, amountNaira: cashGiven),
          if (changeGiven > 0)
            PaymentLine(method: PaymentMethod.cash, amountNaira: -changeGiven),
        ];
      case PaymentMethod.card:
      case PaymentMethod.transfer:
        return [PaymentLine(method: method, amountNaira: total)];
      case PaymentMethod.customerAccount:
        return [
          PaymentLine(
            method: PaymentMethod.customerAccount,
            amountNaira: total,
            customerId: data['customerId'] as String?,
            customerName: data['customerName'] as String?,
          ),
        ];
    }
  }

  @override
  Stream<List<Sale>> watchSales() {
    return _salesCollection.orderBy('createdAt', descending: true).snapshots().map(
      (snapshot) => snapshot.docs.map(_saleFromDoc).toList(),
    );
  }

  @override
  Future<void> recordSale(Sale sale) async {
    await _salesCollection.doc(sale.id).set(saleToDoc(sale));
  }
}
