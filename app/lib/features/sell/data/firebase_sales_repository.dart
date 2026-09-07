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
  static Map<String, dynamic> saleToDoc(Sale sale) => {
    'receiptNumber': sale.receiptNumber,
    'items': sale.items.map(cartLineToMap).toList(),
    'subtotal': sale.subtotal,
    'total': sale.total,
    'method': sale.method.name,
    'cashGiven': sale.cashGiven,
    'changeGiven': sale.changeGiven,
    'customerId': sale.customerId,
    'customerName': sale.customerName,
    'staffId': sale.staffId,
    'staffName': sale.staffName,
    'createdAt': Timestamp.fromDate(sale.createdAt),
  };

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
      method: PaymentMethod.values.byName(data['method'] as String),
      cashGiven: (data['cashGiven'] as num?)?.toInt(),
      changeGiven: (data['changeGiven'] as num?)?.toInt(),
      customerId: data['customerId'] as String?,
      customerName: data['customerName'] as String?,
      staffId: data['staffId'] as String,
      staffName: data['staffName'] as String,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
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
