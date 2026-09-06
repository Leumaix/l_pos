import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:leumadepos/features/auth/data/firebase_auth_repository.dart';
import 'package:leumadepos/features/auth/data/local_credential_store.dart';
import 'package:leumadepos/features/shift/data/firebase_shift_repository.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _StubAuthRepository extends FirebaseAuthRepository {
  _StubAuthRepository(this._firestore)
    : super(store: InMemoryCredentialStore());

  final FirebaseFirestore _firestore;

  @override
  FirebaseFirestore? get activeFirestore => _firestore;
}

void main() {
  late _MockFirebaseFirestore firestore;
  late _MockDocumentReference docRef;
  late _MockDocumentSnapshot snapshot;
  late FirebaseShiftRepository repository;

  setUp(() {
    firestore = _MockFirebaseFirestore();
    docRef = _MockDocumentReference();
    snapshot = _MockDocumentSnapshot();

    when(() => firestore.doc(any())).thenReturn(docRef);
    when(() => docRef.get()).thenAnswer((_) async => snapshot);

    repository = FirebaseShiftRepository(_StubAuthRepository(firestore));
  });

  group('FirebaseShiftRepository — openedAt null-guard (fetchCurrentShift)', () {
    test('returns null when the shift-state doc has no data (no shift open)', () async {
      when(() => snapshot.data()).thenReturn(null);
      final result = await repository.fetchCurrentShift();
      expect(result, isNull);
    });

    test(
      'returns null when openedAt is missing — the pending, '
      'not-yet-resolved FieldValue.serverTimestamp() write — instead of throwing',
      () async {
        when(() => snapshot.data()).thenReturn({
          'openingFloatNaira': 5000,
          'openedByStaffId': 'staff-1',
          'openedByStaffName': 'Amaka',
          'openedAt': null,
          'cashTotalNaira': 0,
          'cardTotalNaira': 0,
          'transferTotalNaira': 0,
          'creditTotalNaira': 0,
          'salesCount': 0,
        });
        final result = await repository.fetchCurrentShift();
        expect(result, isNull);
      },
    );

    test('returns null when openedAt is some other non-Timestamp value', () async {
      when(() => snapshot.data()).thenReturn({
        'openingFloatNaira': 5000,
        'openedByStaffId': 'staff-1',
        'openedByStaffName': 'Amaka',
        'openedAt': 'not-a-timestamp',
        'cashTotalNaira': 0,
        'cardTotalNaira': 0,
        'transferTotalNaira': 0,
        'creditTotalNaira': 0,
        'salesCount': 0,
      });
      final result = await repository.fetchCurrentShift();
      expect(result, isNull);
    });

    test(
      'returns a real OpenShift once openedAt has resolved to a Timestamp '
      '(control case — proves the guard is not just returning null unconditionally)',
      () async {
        final openedAt = DateTime(2026, 9, 6, 8, 30);
        when(() => snapshot.data()).thenReturn({
          'openingFloatNaira': 5000,
          'openedByStaffId': 'staff-1',
          'openedByStaffName': 'Amaka',
          'openedAt': Timestamp.fromDate(openedAt),
          'cashTotalNaira': 1000,
          'cardTotalNaira': 500,
          'transferTotalNaira': 200,
          'creditTotalNaira': 0,
          'salesCount': 3,
        });
        final result = await repository.fetchCurrentShift();
        expect(result, isNotNull);
        expect(result!.openingFloatNaira, 5000);
        expect(result.openedByStaffId, 'staff-1');
        expect(result.openedAt, openedAt);
        expect(result.salesCount, 3);
      },
    );
  });
}
