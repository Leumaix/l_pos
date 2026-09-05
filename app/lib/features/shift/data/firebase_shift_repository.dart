import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/business_config.dart';
import '../../auth/data/firebase_auth_repository.dart';
import '../domain/shift.dart';
import 'shift_repository.dart';

/// Real implementation — reads/writes through whoever is CURRENTLY
/// ACTIVE's authenticated Firestore session, same pattern as every other
/// Firebase-backed repository in this app.
///
/// shiftState/current exists ⟺ a shift is open (no separate status
/// field) — this is what firestore.rules' exists() check on /sales
/// create relies on, and what makes "block opening while one's already
/// open" fall out of Firestore's own create-vs-update classification for
/// free, with no extra staleness check needed.
///
/// closeDay archives to shiftHistory at a PRE-MINTED id (plannedHistoryId,
/// written onto shiftState/current at open time) rather than an auto-id —
/// firestore.rules' delete rule pairs the shiftState/current delete with
/// a getAfter() check on that exact id, the same way
/// FirebaseCustomerRepository pairs a balance update with its ledger
/// entry. A delete has no request.resource.data to carry a pointer field
/// the way an update does, so the pointer has to already be sitting on
/// the doc being deleted — hence minting it up front at open time.
class FirebaseShiftRepository implements ShiftRepository {
  final FirebaseAuthRepository _firebaseAuth;

  OpenShift? _cachedShift;
  StreamSubscription<OpenShift?>? _shiftSubscription;

  FirebaseShiftRepository(this._firebaseAuth);

  FirebaseFirestore get _firestore {
    final firestore = _firebaseAuth.activeFirestore;
    if (firestore == null) {
      throw StateError('ShiftRepository used with nobody currently signed in.');
    }
    return firestore;
  }

  DocumentReference<Map<String, dynamic>> get _shiftStateDoc =>
      _firestore.doc('businesses/$kBusinessId/shiftState/current');

  CollectionReference<Map<String, dynamic>> get _shiftHistoryCollection =>
      _firestore.collection('businesses/$kBusinessId/shiftHistory');

  OpenShift? _openShiftFromData(Map<String, dynamic>? data) {
    if (data == null) return null;
    return OpenShift(
      openingFloatNaira: (data['openingFloatNaira'] as num).toInt(),
      openedByStaffId: data['openedByStaffId'] as String,
      openedByStaffName: data['openedByStaffName'] as String,
      openedAt: (data['openedAt'] as Timestamp).toDate(),
      cashTotalNaira: (data['cashTotalNaira'] as num).toInt(),
      cardTotalNaira: (data['cardTotalNaira'] as num).toInt(),
      transferTotalNaira: (data['transferTotalNaira'] as num).toInt(),
      creditTotalNaira: (data['creditTotalNaira'] as num).toInt(),
      salesCount: (data['salesCount'] as num).toInt(),
    );
  }

  ClosedShift _closedShiftFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ClosedShift(
      openingFloatNaira: (data['openingFloatNaira'] as num).toInt(),
      openedByStaffId: data['openedByStaffId'] as String,
      openedByStaffName: data['openedByStaffName'] as String,
      openedAt: (data['openedAt'] as Timestamp).toDate(),
      cashTotalNaira: (data['cashTotalNaira'] as num).toInt(),
      cardTotalNaira: (data['cardTotalNaira'] as num).toInt(),
      transferTotalNaira: (data['transferTotalNaira'] as num).toInt(),
      creditTotalNaira: (data['creditTotalNaira'] as num).toInt(),
      salesCount: (data['salesCount'] as num).toInt(),
      countedCashNaira: (data['countedCashNaira'] as num).toInt(),
      varianceNaira: (data['varianceNaira'] as num).toInt(),
      closedByStaffId: data['closedByStaffId'] as String,
      closedByStaffName: data['closedByStaffName'] as String,
      closedAt: (data['closedAt'] as Timestamp).toDate(),
    );
  }

  @override
  Stream<OpenShift?> watchCurrentShift() {
    // Deliberately does NOT touch _shiftStateDoc (and therefore
    // _firestore) synchronously at call time — this is wired into
    // app_router.dart's refreshListenable, which is built ONCE at router
    // construction, before anyone is signed in. Evaluating _firestore
    // that early throws (activeFirestore is null pre-sign-in). Instead,
    // this switches to the real Firestore stream only once
    // authStateChanges() actually reports someone signed in, and back to
    // a bare `null` the moment nobody is — never throws, regardless of
    // when or how early it's subscribed to.
    return _firebaseAuth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(null);
      final firestore = _firebaseAuth.activeFirestore!;
      return firestore
          .doc('businesses/$kBusinessId/shiftState/current')
          .snapshots()
          .map((doc) => _openShiftFromData(doc.data()));
    });
  }

  @override
  OpenShift? get currentShift {
    _shiftSubscription ??= watchCurrentShift().listen((shift) => _cachedShift = shift);
    return _cachedShift;
  }

  @override
  Future<OpenShift?> fetchCurrentShift() async {
    // One fresh .get(), not the cached currentShift getter — see this
    // method's doc comment on the interface for why that can still be
    // showing null the first time it's ever accessed.
    final doc = await _shiftStateDoc.get();
    return _openShiftFromData(doc.data());
  }

  @override
  Future<void> openDay({required int openingFloatNaira, required String staffId, required String staffName}) async {
    // Minted now, stored on the doc, and referenced later by
    // firestore.rules' delete rule — see this class's doc comment.
    final historyRef = _shiftHistoryCollection.doc();
    try {
      // A plain (non-merge) set(), not a special "create" API — the
      // client SDK has no document-level create precondition of its own.
      // firestore.rules is what actually enforces this: it classifies
      // this write as create-vs-update based on whether the doc existed
      // BEFORE this request, and only `allow create` matches — so a set()
      // against an already-open shift is rejected as an unauthorized
      // update, not silently accepted as a fresh open.
      await _shiftStateDoc.set({
        'openingFloatNaira': openingFloatNaira,
        'openedByStaffId': staffId,
        'openedByStaffName': staffName,
        'openedAt': FieldValue.serverTimestamp(),
        'cashTotalNaira': 0,
        'cardTotalNaira': 0,
        'transferTotalNaira': 0,
        'creditTotalNaira': 0,
        'salesCount': 0,
        'plannedHistoryId': historyRef.id,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const ShiftAlreadyOpenException();
      }
      rethrow;
    }
  }

  @override
  Future<ClosedShift> closeDay({
    required int countedCashNaira,
    required String staffId,
    required String staffName,
  }) async {
    late final ClosedShift closed;
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(_shiftStateDoc);
      final data = snapshot.data();
      if (data == null) throw const NoShiftOpenException();

      final shift = _openShiftFromData(data)!;
      final closedAt = DateTime.now();
      closed = closeShift(
        shift,
        countedCashNaira: countedCashNaira,
        staffId: staffId,
        staffName: staffName,
        closedAt: closedAt,
      );

      final historyId = data['plannedHistoryId'] as String;
      transaction.set(_shiftHistoryCollection.doc(historyId), {
        'openingFloatNaira': closed.openingFloatNaira,
        'openedByStaffId': closed.openedByStaffId,
        'openedByStaffName': closed.openedByStaffName,
        'openedAt': data['openedAt'],
        'cashTotalNaira': closed.cashTotalNaira,
        'cardTotalNaira': closed.cardTotalNaira,
        'transferTotalNaira': closed.transferTotalNaira,
        'creditTotalNaira': closed.creditTotalNaira,
        'salesCount': closed.salesCount,
        'countedCashNaira': closed.countedCashNaira,
        'expectedCashNaira': closed.expectedCashNaira,
        'varianceNaira': closed.varianceNaira,
        'closedByStaffId': closed.closedByStaffId,
        'closedByStaffName': closed.closedByStaffName,
        'closedAt': FieldValue.serverTimestamp(),
      });
      transaction.delete(_shiftStateDoc);
    });
    return closed;
  }

  @override
  Stream<List<ClosedShift>> watchShiftHistory() {
    return _shiftHistoryCollection.orderBy('closedAt', descending: true).snapshots().map(
      (snapshot) => snapshot.docs.map(_closedShiftFromDoc).toList(),
    );
  }
}
