import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_auth_repository.dart';

/// Thrown when the entered business id already has a document — a clean
/// client-side error instead of a raw permission-denied (once the doc
/// exists, firestore.rules' `allow create` on /businesses/{businessId}
/// no longer applies and the write would be classified as a denied
/// update instead).
class BusinessIdTakenException implements Exception {
  const BusinessIdTakenException();
}

/// The super-admin onboarding tool's one job: exactly two writes — create
/// the business, create its first-owner invite. Everything after that
/// (the owner opening the invite email, choosing a PIN, landing on Home)
/// reuses the mobile app's existing, already-tested
/// FirebaseAuthRepository._loadStaffDoc self-provisioning flow untouched
/// — this repository never touches /staff at all.
abstract class BusinessOnboardingRepository {
  Future<void> onboardBusiness({
    required String businessId,
    required String businessName,
    required String ownerName,
    required String ownerEmail,
  });
}

/// Real implementation — reads/writes through the DEFAULT FirebaseFirestore
/// instance (there's no per-staff secondary FirebaseApp concept here; the
/// admin tool signs in once, plainly, via FirebaseAdminAuthRepository).
class FirebaseBusinessOnboardingRepository implements BusinessOnboardingRepository {
  final AdminAuthRepository _adminAuth;
  final FirebaseFirestore _firestore;

  FirebaseBusinessOnboardingRepository(this._adminAuth, {FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<void> onboardBusiness({
    required String businessId,
    required String businessName,
    required String ownerName,
    required String ownerEmail,
  }) async {
    final admin = _adminAuth.currentUser;
    if (admin == null) {
      throw StateError('onboardBusiness called with nobody currently signed in.');
    }

    final normalizedBusinessId = businessId.trim();
    final businessRef = _firestore.doc('businesses/$normalizedBusinessId');

    // Checked up front, not inferred from a failed write — firestore.rules
    // classifies a set() against an EXISTING doc as an update, which the
    // super-admin has no carve-out for, so a taken id would otherwise
    // surface as an opaque permission-denied rather than this clear error.
    final existing = await businessRef.get();
    if (existing.exists) {
      throw const BusinessIdTakenException();
    }

    await businessRef.set({'name': businessName.trim()});

    final normalizedEmail = ownerEmail.trim().toLowerCase();
    // Same invite document shape FirebaseStaffInviteRepository.createInvite
    // already writes for ordinary staff — role 'owner' is the only
    // difference, reaching Firestore through the super-admin rules
    // carve-out (isPlatformSuperAdmin()) instead of isActiveOwnerOf, since
    // this business has no owner yet to satisfy that check.
    await _firestore.doc('businesses/$normalizedBusinessId/invites/$normalizedEmail').set({
      'name': ownerName.trim(),
      'role': 'owner',
      'invitedAt': FieldValue.serverTimestamp(),
      'invitedBy': admin.uid,
    });
  }
}

/// In-memory stand-in for tests and the debug entry point.
class FakeBusinessOnboardingRepository implements BusinessOnboardingRepository {
  final Set<String> _businessIds = {};

  /// Test-only record of what got onboarded, in call order.
  final List<
    ({String businessId, String businessName, String ownerName, String ownerEmail})
  >
  onboarded = [];

  @override
  Future<void> onboardBusiness({
    required String businessId,
    required String businessName,
    required String ownerName,
    required String ownerEmail,
  }) async {
    final normalizedId = businessId.trim();
    if (_businessIds.contains(normalizedId)) {
      throw const BusinessIdTakenException();
    }
    _businessIds.add(normalizedId);
    onboarded.add((
      businessId: normalizedId,
      businessName: businessName.trim(),
      ownerName: ownerName.trim(),
      ownerEmail: ownerEmail.trim().toLowerCase(),
    ));
  }
}
