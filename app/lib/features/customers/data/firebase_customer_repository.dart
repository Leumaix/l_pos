import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/business_config.dart';
import '../../auth/data/firebase_auth_repository.dart';
import '../domain/customer.dart';
import '../domain/customer_transaction.dart';
import 'customer_repository.dart';

/// Real implementation — reads/writes through whoever is CURRENTLY
/// ACTIVE's authenticated Firestore session (see
/// FirebaseAuthRepository.activeFirestore), same pattern as every other
/// Firebase-backed repository in this app.
///
/// recordCreditSale/recordRepayment use runTransaction rather than a
/// blind FieldValue.increment: this is real money owed by real
/// customers, so balanceAfter has to be the true post-write balance, not
/// a best-effort guess. A transaction reads the current balance,
/// computes the exact new one, and writes both the customer's balance
/// and an accurate transaction-ledger entry atomically — Firestore
/// retries the whole transaction automatically if it races a concurrent
/// write, closing the gap a blind increment would leave open.
class FirebaseCustomerRepository implements CustomerRepository {
  final FirebaseAuthRepository _firebaseAuth;

  FirebaseCustomerRepository(this._firebaseAuth);

  FirebaseFirestore get _firestore {
    final firestore = _firebaseAuth.activeFirestore;
    if (firestore == null) {
      throw StateError('CustomerRepository used with nobody currently signed in.');
    }
    return firestore;
  }

  CollectionReference<Map<String, dynamic>> get _customersCollection =>
      _firestore.collection('businesses/$kBusinessId/customers');

  Customer _customerFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Customer(
      id: doc.id,
      name: data['name'] as String,
      phone: data['phone'] as String,
      balance: (data['balance'] as num).toInt(),
    );
  }

  static const _typeNames = {
    CustomerTransactionType.creditSale: 'creditSale',
    CustomerTransactionType.repayment: 'repayment',
    CustomerTransactionType.openingBalance: 'openingBalance',
  };

  CustomerTransaction _transactionFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return CustomerTransaction(
      id: doc.id,
      type: _typeNames.entries.firstWhere((e) => e.value == data['type']).key,
      amountNaira: (data['amountNaira'] as num).toInt(),
      balanceAfter: (data['balanceAfter'] as num).toInt(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      saleId: data['saleId'] as String?,
    );
  }

  @override
  Stream<List<Customer>> watchCustomers() {
    return _customersCollection.snapshots().map(
      (snapshot) => snapshot.docs.map(_customerFromDoc).toList(),
    );
  }

  @override
  Stream<List<CustomerTransaction>> watchTransactions(String customerId) {
    return _customersCollection
        .doc(customerId)
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_transactionFromDoc).toList());
  }

  @override
  Future<Customer> createCustomer({
    required String name,
    required String phone,
    int openingBalanceNaira = 0,
  }) async {
    final ref = _customersCollection.doc();
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();

    if (openingBalanceNaira == 0) {
      // No transaction doc needed — firestore.rules' create-time guard
      // (owner-or-zero) is what actually enforces this path is safe;
      // the paired-write/lastTransactionId check only governs updates.
      await ref.set({'name': trimmedName, 'phone': trimmedPhone, 'balance': 0});
      return Customer(id: ref.id, name: trimmedName, phone: trimmedPhone, balance: 0);
    }

    final txRef = ref.collection('transactions').doc();
    await _firestore.runTransaction((transaction) async {
      transaction.set(ref, {
        'name': trimmedName,
        'phone': trimmedPhone,
        'balance': openingBalanceNaira,
        'lastTransactionId': txRef.id,
      });
      transaction.set(txRef, {
        'type': _typeNames[CustomerTransactionType.openingBalance],
        'amountNaira': openingBalanceNaira.abs(),
        'balanceAfter': openingBalanceNaira,
        'createdAt': FieldValue.serverTimestamp(),
        'saleId': null,
      });
    });
    return Customer(id: ref.id, name: trimmedName, phone: trimmedPhone, balance: openingBalanceNaira);
  }

  Future<void> _applyBalanceChange(
    String customerId,
    int delta,
    CustomerTransactionType type, {
    String? saleId,
  }) async {
    final customerRef = _customersCollection.doc(customerId);
    final txRef = customerRef.collection('transactions').doc();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(customerRef);
      final currentBalance = (snapshot.data()?['balance'] as num? ?? 0).toInt();
      final newBalance = currentBalance + delta;

      // lastTransactionId is what lets firestore.rules verify this
      // update is paired with the ledger entry below, in this exact
      // same write — see the rule's own doc comment for why that's
      // needed to close a real fraud vector.
      transaction.update(customerRef, {'balance': newBalance, 'lastTransactionId': txRef.id});
      transaction.set(txRef, {
        'type': _typeNames[type],
        'amountNaira': delta.abs(),
        'balanceAfter': newBalance,
        'createdAt': FieldValue.serverTimestamp(),
        'saleId': saleId,
      });
    });
  }

  @override
  Future<void> recordCreditSale({required String customerId, required int amountNaira, String? saleId}) {
    return _applyBalanceChange(customerId, amountNaira, CustomerTransactionType.creditSale, saleId: saleId);
  }

  @override
  Future<void> recordRepayment({required String customerId, required int amountNaira}) {
    return _applyBalanceChange(customerId, -amountNaira, CustomerTransactionType.repayment);
  }
}
