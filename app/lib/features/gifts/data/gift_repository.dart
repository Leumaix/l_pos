import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/business_config.dart';
import '../../auth/data/auth_repository.dart';
import '../../sell/data/inventory_repository.dart';
import '../../shift/data/shift_repository.dart';
import '../domain/gift.dart';

/// The atomic commit step of a gift — mirrors CheckoutRepository's shape
/// (a fresh id minted up front, then one atomic commit) and
/// FirebaseCheckoutRepository.commitSale's OWN stock-deduction exactly
/// (same gasStock/gasStockLedger/products writes, same "no client-side
/// oversell guard, the products/{id} rule's stockCount >= 0 is the only
/// enforcement, gas has none by design" trust boundary — see the
/// gifting design doc's own flagged note on this).
abstract class GiftRepository {
  /// A fresh, globally-unique gift id, minted before anything else —
  /// needed up front because, for an over-threshold gift, the SAME id
  /// is reused for the giftApprovals doc (see [recordOwnerApproval]).
  String newGiftId();

  /// Records that [ownerUid] approved gift [giftId] — called only after
  /// AuthRepository.verifyActiveOwnerPin has already confirmed
  /// [ownerUid] really is that owner's own uid for [ownerEmail]. The
  /// real implementation performs this write AS the owner's own
  /// authenticated session (via AuthRepository.firestoreForEmail), so
  /// firestore.rules' request.auth.uid check on giftApprovals/{giftId}
  /// is genuine, not merely a client-side PIN check that was verified
  /// and then discarded. Throws if that session isn't available (e.g.
  /// the owner has never verified this device).
  Future<void> recordOwnerApproval({
    required String giftId,
    required String ownerEmail,
    required String ownerUid,
  });

  /// Commits the gift record and its stock deduction as one atomic
  /// write: gasStock/current + a gasStockLedger entry for a gas gift,
  /// or the product's stockCount for a product gift — never both.
  /// [gasUnitsDeducted] is the caller's own already-computed
  /// gas_stock.sellByKg(...).unitsDeducted (kg → units conversion is
  /// NOT this repository's job, same division of labor commitSale/cart
  /// already established), null/unused for a product gift.
  ///
  /// Throws [NoShiftOpenException] if no shift is currently open — a
  /// gift can never be recorded outside an open business day, same
  /// boundary as a sale. For an over-threshold gift, also throws if the
  /// paired giftApprovals doc is missing (never called, or already
  /// consumed) — firestore.rules independently enforces this same
  /// pairing server-side either way.
  Future<void> commitGift({required Gift gift, int? gasUnitsDeducted});
}

/// In-memory stand-in — delegates to the fakes it's handed, same
/// division of labor FakeCheckoutRepository already uses (gas/product
/// deduction goes through FakeInventoryRepository, shift-open gating
/// through FakeShiftRepository). Owner approval is recorded purely
/// in-memory here — no real Firestore/AuthRepository dependency at all,
/// since this fake never touches either.
class FakeGiftRepository implements GiftRepository {
  final FakeInventoryRepository _inventory;
  final FakeShiftRepository _shift;
  final List<Gift> _gifts = [];
  final Map<String, String> _approvals = {}; // giftId -> ownerUid

  FakeGiftRepository({required this._inventory, required this._shift});

  int _idCounter = 0;

  @override
  String newGiftId() => 'gift-fake-${_idCounter++}';

  @override
  Future<void> recordOwnerApproval({
    required String giftId,
    required String ownerEmail,
    required String ownerUid,
  }) async {
    _approvals[giftId] = ownerUid;
  }

  @override
  Future<void> commitGift({required Gift gift, int? gasUnitsDeducted}) async {
    if (_shift.currentShift == null) throw const NoShiftOpenException();
    if (gift.requiresApproval && _approvals[gift.id] != gift.approvedByOwnerUid) {
      throw const GiftApprovalMissingException();
    }

    if (gift.itemType == GiftItemType.gas) {
      await _inventory.deductGasStock(gasUnitsDeducted ?? 0, staffId: gift.staffId, staffName: gift.staffName);
    } else {
      await _inventory.decrementProductStock(gift.productId!, gift.quantity.round());
    }

    _gifts.add(gift);
    _approvals.remove(gift.id); // consumed — same single-use shape as the real giftApprovals delete
  }

  /// Test-only visibility into what's been recorded so far.
  List<Gift> get debugGifts => List.unmodifiable(_gifts);
}

/// Thrown by [FakeGiftRepository.commitGift] mirroring the real
/// implementation's equivalent firestore.rules rejection — an
/// over-threshold gift committed with no matching (or already-consumed)
/// owner approval. The real implementation doesn't throw this client-side
/// (see that class's own doc comment) — the rules themselves reject the
/// write, surfacing as a generic Firestore permission error; this fake
/// makes the same boundary visible and named for tests.
class GiftApprovalMissingException implements Exception {
  const GiftApprovalMissingException();
}

class FirebaseGiftRepository implements GiftRepository {
  final AuthRepository _firebaseAuth;

  FirebaseGiftRepository(this._firebaseAuth);

  FirebaseFirestore get _firestore {
    final firestore = _firebaseAuth.activeFirestore;
    if (firestore == null) {
      throw StateError('GiftRepository used with nobody currently signed in.');
    }
    return firestore;
  }

  CollectionReference<Map<String, dynamic>> get _giftsCollection =>
      _firestore.collection('businesses/$kBusinessId/gifts');

  DocumentReference<Map<String, dynamic>> get _gasStockDoc =>
      _firestore.doc('businesses/$kBusinessId/gasStock/current');

  CollectionReference<Map<String, dynamic>> get _gasStockLedgerCollection =>
      _firestore.collection('businesses/$kBusinessId/gasStockLedger');

  CollectionReference<Map<String, dynamic>> get _productsCollection =>
      _firestore.collection('businesses/$kBusinessId/products');

  DocumentReference<Map<String, dynamic>> get _shiftStateDoc =>
      _firestore.doc('businesses/$kBusinessId/shiftState/current');

  @override
  String newGiftId() => _giftsCollection.doc().id;

  @override
  Future<void> recordOwnerApproval({
    required String giftId,
    required String ownerEmail,
    required String ownerUid,
  }) async {
    // AS the owner's own authenticated session — never _firestore (the
    // CALLER's, i.e. whichever staff member is recording the gift)
    // above. This is what makes firestore.rules' request.auth.uid ==
    // approvedByOwnerUid check on the create rule genuine.
    final ownerFirestore = _firebaseAuth.firestoreForEmail(ownerEmail);
    if (ownerFirestore == null) {
      throw StateError('recordOwnerApproval: no cached session for $ownerEmail — was verifyActiveOwnerPin called first?');
    }
    await ownerFirestore.doc('businesses/$kBusinessId/giftApprovals/$giftId').set({
      'approvedByOwnerUid': ownerUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> commitGift({required Gift gift, int? gasUnitsDeducted}) async {
    await _firestore.runTransaction((transaction) async {
      // All reads first — a Firestore transaction requires it.
      final shiftSnapshot = await transaction.get(_shiftStateDoc);
      if (!shiftSnapshot.exists) throw const NoShiftOpenException();

      transaction.set(_giftsCollection.doc(gift.id), _giftToDoc(gift));

      if (gift.requiresApproval) {
        // Anti-replay consumption — see firestore.rules' matching
        // pairing check on giftApprovals' own delete rule (getAfter()
        // on this exact gift id).
        transaction.delete(_firestore.doc('businesses/$kBusinessId/giftApprovals/${gift.id}'));
      }

      if (gift.itemType == GiftItemType.gas) {
        final units = gasUnitsDeducted ?? 0;
        transaction.set(_gasStockDoc, {'units': FieldValue.increment(-units)}, SetOptions(merge: true));
        transaction.set(_gasStockLedgerCollection.doc(), {
          'type': 'gift',
          'unitsDelta': -units,
          'staffId': gift.staffId,
          'staffName': gift.staffName,
          'giftId': gift.id,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Server-side oversell guard lives in firestore.rules
        // (stockCount >= 0 on the resulting write) — a blind increment
        // here, rejected by the rule if it would go negative. Same
        // trust boundary as commitSale's own product-line deduction.
        transaction.update(_productsCollection.doc(gift.productId), {
          'stockCount': FieldValue.increment(-gift.quantity.round()),
        });
      }
    });
  }

  static Map<String, dynamic> _giftToDoc(Gift gift) => {
    'itemType': gift.itemType.name,
    'productId': gift.productId,
    'quantity': gift.quantity,
    'estimatedValueNaira': gift.estimatedValueNaira,
    'reason': gift.reason,
    'staffId': gift.staffId,
    'staffName': gift.staffName,
    'shiftId': gift.shiftId,
    'requiresApproval': gift.requiresApproval,
    'approvedByOwnerUid': gift.approvedByOwnerUid,
    'createdAt': FieldValue.serverTimestamp(),
  };
}
