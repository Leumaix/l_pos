import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:leumadepos/features/auth/data/auth_repository.dart';
import 'package:leumadepos/features/auth/data/firebase_auth_repository.dart';
import 'package:leumadepos/features/auth/data/local_credential_store.dart';
import 'package:leumadepos/features/shift/data/firebase_shift_repository.dart';
import 'package:leumadepos/features/shift/domain/shift.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockSnapshotMetadata extends Mock implements SnapshotMetadata {}

const _testUser = AppUser(uid: 'staff-1', name: 'Amaka', email: 'amaka@leumadepos.test', role: 'attendant');

/// Overrides authStateChanges() too (not just activeFirestore) — the real
/// FirebaseAuthRepository's version is pure Dart (no plugin channel), but
/// starts with nobody signed in, and watchCurrentShift's whole Firestore
/// path is gated behind a non-null user.
class _StubAuthRepository extends FirebaseAuthRepository {
  _StubAuthRepository(this._firestore)
    : super(store: InMemoryCredentialStore());

  final FirebaseFirestore _firestore;

  @override
  FirebaseFirestore? get activeFirestore => _firestore;

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_testUser);
}

Map<String, dynamic> _openShiftData({String staffId = 'staff-1'}) => {
  'openingFloatNaira': 10000,
  'openedByStaffId': staffId,
  'openedByStaffName': 'Amaka',
  'openedAt': Timestamp.fromDate(DateTime(2026, 9, 12, 8)),
  'cashTotalNaira': 0,
  'cardTotalNaira': 0,
  'transferTotalNaira': 0,
  'creditTotalNaira': 0,
  'salesCount': 0,
  'expenseTotalNaira': 0,
  'plannedHistoryId': 'hist-1',
};

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
          'expenseTotalNaira': 0,
          'plannedHistoryId': 'hist-1',
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

  group('FirebaseShiftRepository — watchCurrentShift trusts only server-confirmed snapshots', () {
    _MockDocumentSnapshot mockSnapshot({
      required Map<String, dynamic>? data,
      required bool isFromCache,
      required bool hasPendingWrites,
    }) {
      final snap = _MockDocumentSnapshot();
      final metadata = _MockSnapshotMetadata();
      when(() => metadata.isFromCache).thenReturn(isFromCache);
      when(() => metadata.hasPendingWrites).thenReturn(hasPendingWrites);
      when(() => snap.data()).thenReturn(data);
      when(() => snap.metadata).thenReturn(metadata);
      return snap;
    }

    test(
      'reproduces the live bug: a stale cached "no shift" snapshot arriving before the real, '
      'server-confirmed "shift is open" one is never emitted — the UI must never see "no shift" '
      'for a business day that is actually still open',
      () async {
        final controller = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
        when(
          () => docRef.snapshots(includeMetadataChanges: true),
        ).thenAnswer((_) => controller.stream);

        final emitted = <OpenShift?>[];
        final subscription = repository.watchCurrentShift().listen(emitted.add);
        await Future<void>.delayed(Duration.zero);

        // The stale, untrustworthy read — exactly what a fresh listener
        // can deliver from local persistence before the server round-trip
        // completes. This is the snapshot that, before the fix, made Home
        // show "Open the day" for a shift that was genuinely still open.
        controller.add(mockSnapshot(data: null, isFromCache: true, hasPendingWrites: false));
        await Future<void>.delayed(Duration.zero);
        expect(emitted, isEmpty, reason: 'the untrustworthy cached snapshot must not be emitted at all');

        // The real, server-confirmed answer arrives: a shift genuinely is
        // open (this is what the live production doc actually held).
        controller.add(
          mockSnapshot(data: _openShiftData(), isFromCache: false, hasPendingWrites: false),
        );
        await Future<void>.delayed(Duration.zero);

        expect(emitted, hasLength(1));
        expect(emitted.single, isNotNull);
        expect(emitted.single!.openedByStaffId, 'staff-1');

        await subscription.cancel();
        await controller.close();
      },
    );

    test('a trustworthy, server-confirmed "no shift" snapshot IS emitted as null — proves the fix '
        "doesn't just suppress every null forever, only untrustworthy ones", () async {
      final controller = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      when(() => docRef.snapshots(includeMetadataChanges: true)).thenAnswer((_) => controller.stream);

      final emitted = <OpenShift?>[];
      final subscription = repository.watchCurrentShift().listen(emitted.add);
      await Future<void>.delayed(Duration.zero);

      controller.add(mockSnapshot(data: null, isFromCache: false, hasPendingWrites: false));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      expect(emitted.single, isNull);

      await subscription.cancel();
      await controller.close();
    });

    test('a snapshot reflecting our own in-flight write (hasPendingWrites) is skipped even when '
        "it's not from cache — matches the existing openedAt-pending guard's own reasoning", () async {
      final controller = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      when(() => docRef.snapshots(includeMetadataChanges: true)).thenAnswer((_) => controller.stream);

      final emitted = <OpenShift?>[];
      final subscription = repository.watchCurrentShift().listen(emitted.add);
      await Future<void>.delayed(Duration.zero);

      controller.add(mockSnapshot(data: _openShiftData(), isFromCache: false, hasPendingWrites: true));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);

      controller.add(mockSnapshot(data: _openShiftData(), isFromCache: false, hasPendingWrites: false));
      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
      expect(emitted.single, isNotNull);

      await subscription.cancel();
      await controller.close();
    });
  });
}
