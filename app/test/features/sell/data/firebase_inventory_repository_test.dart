import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_stock/gas_stock.dart';
import 'package:mocktail/mocktail.dart';

import 'package:leumadepos/features/auth/data/firebase_auth_repository.dart';
import 'package:leumadepos/features/auth/data/local_credential_store.dart';
import 'package:leumadepos/features/sell/data/firebase_inventory_repository.dart';

// Mocktail can't reliably stub a generic method whose type parameter
// affects its return type (runTransaction<T>, Transaction.set<T>) via
// when()/any() — the synthesized fallback return value construction
// throws. Both are overridden concretely below instead: runTransaction
// just invokes the handler with the test's own mock Transaction, and
// set() records each write for assertions rather than going through
// verify()/captureAny(). Every other method here still uses ordinary
// Mock/when() stubbing.
class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {
  _MockFirebaseFirestore(this._transaction);

  final Transaction _transaction;

  @override
  Future<T> runTransaction<T>(
    Future<T> Function(Transaction) transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    return transactionHandler(_transaction);
  }
}

class _MockTransaction extends Mock implements Transaction {
  final writes = <MapEntry<DocumentReference, Map<String, dynamic>>>[];

  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data, [SetOptions? options]) {
    writes.add(MapEntry(documentReference, data as Map<String, dynamic>));
    return this;
  }
}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _StubAuthRepository extends FirebaseAuthRepository {
  _StubAuthRepository(this._firestore) : super(store: InMemoryCredentialStore());

  final FirebaseFirestore _firestore;

  @override
  FirebaseFirestore? get activeFirestore => _firestore;
}

/// Regression coverage for a real bug found on a live business:
/// changeGasRate's "no rate has ever been set" branch used to assume
/// that always meant "no gasStock/current doc exists at all yet," and
/// reset units to 0 unconditionally — silently discarding real stock
/// for a business where ordinary staff sales/restock activity had
/// already created the doc (units only, no rate — see firestore.rules'
/// gasStock create rule) before any owner ever visited Settings.
void main() {
  late _MockFirebaseFirestore firestore;
  late _MockTransaction transaction;
  late _MockDocumentReference gasStockDoc;
  late _MockDocumentSnapshot gasStockSnapshot;
  late _MockCollectionReference ledgerCollection;
  late _MockDocumentReference ledgerDoc;
  late FirebaseInventoryRepository repository;

  setUp(() {
    transaction = _MockTransaction();
    firestore = _MockFirebaseFirestore(transaction);
    gasStockDoc = _MockDocumentReference();
    gasStockSnapshot = _MockDocumentSnapshot();
    ledgerCollection = _MockCollectionReference();
    ledgerDoc = _MockDocumentReference();

    when(() => firestore.doc('businesses/ph-zazaa/gasStock/current')).thenReturn(gasStockDoc);
    when(() => firestore.collection('businesses/ph-zazaa/gasStockLedger')).thenReturn(ledgerCollection);
    when(() => ledgerCollection.doc()).thenReturn(ledgerDoc);
    when(() => transaction.get(gasStockDoc)).thenAnswer((_) async => gasStockSnapshot);

    repository = FirebaseInventoryRepository(_StubAuthRepository(firestore));
  });

  Map<String, dynamic> writeTo(DocumentReference doc) =>
      transaction.writes.firstWhere((w) => w.key == doc).value;

  group('changeGasRate', () {
    test(
      'no rate, and units already recorded (ordinary staff activity created the doc before any '
      'owner set a rate) — preserves physical kg from the implicit default rate, does NOT reset '
      'units to 0',
      () async {
        when(() => gasStockSnapshot.data()).thenReturn({'units': 1116000});

        await repository.changeGasRate(
          const GasRate(1400), // same as the implicit default — no numeric change expected
          staffId: 'staff-1',
          staffName: 'Owner',
        );

        final written = writeTo(gasStockDoc);
        expect(written['rate'], 1400);
        expect(written['units'], 1116000); // unchanged: 1400 -> 1400 preserves kg exactly

        final ledgerEntry = writeTo(ledgerDoc);
        expect(ledgerEntry['type'], 'rateChange');
        expect(ledgerEntry['oldRate'], 1400); // the implicit rate, recorded honestly
        expect(ledgerEntry['unitsDelta'], 0);
      },
    );

    test(
      'no rate, existing units, and a genuinely different new rate — still preserves kg, just '
      're-expressed',
      () async {
        when(() => gasStockSnapshot.data()).thenReturn({'units': 1400}); // 1kg at the implicit 1400 rate

        await repository.changeGasRate(
          const GasRate(1500),
          staffId: 'staff-1',
          staffName: 'Owner',
        );

        final written = writeTo(gasStockDoc);
        expect(written['rate'], 1500);
        expect(written['units'], 1500); // still exactly 1kg, now at 1500/kg
      },
    );

    test('no rate, no prior units at all (a genuinely fresh business) — still initializes at 0, '
        'unchanged from before this fix', () async {
      when(() => gasStockSnapshot.data()).thenReturn(null);

      await repository.changeGasRate(
        const GasRate(1400),
        staffId: 'staff-1',
        staffName: 'Owner',
      );

      final written = writeTo(gasStockDoc);
      expect(written['rate'], 1400);
      expect(written['units'], 0);

      final ledgerEntry = writeTo(ledgerDoc);
      expect(ledgerEntry['type'], 'initialize');
      expect(ledgerEntry['oldRate'], isNull);
    });

    test(
      'a real rate already exists — ordinary rate change, unaffected by this fix',
      () async {
        when(() => gasStockSnapshot.data()).thenReturn({'rate': 1400, 'units': 63000}); // 45kg

        await repository.changeGasRate(
          const GasRate(1500),
          staffId: 'staff-1',
          staffName: 'Owner',
        );

        final written = writeTo(gasStockDoc);
        expect(written['rate'], 1500);
        expect(written['units'], 67500); // 45kg preserved at the new rate

        final ledgerEntry = writeTo(ledgerDoc);
        expect(ledgerEntry['type'], 'rateChange');
        expect(ledgerEntry['oldRate'], 1400);
      },
    );
  });
}
