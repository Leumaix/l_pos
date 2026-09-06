import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/business_config.dart';
import '../domain/staff_invite.dart';
import 'auth_repository.dart';
import 'staff_invite_repository.dart';

/// Real implementation — reads/writes through whoever is CURRENTLY
/// ACTIVE's authenticated Firestore session (see
/// FirebaseAuthRepository.activeFirestore), since that's the identity
/// Firestore rules check (isActiveOwnerOf). Only meaningful when an
/// owner is signed in; the security rules are the real enforcement of
/// that, this just throws a clearer error if called with nobody active.
class FirebaseStaffInviteRepository implements StaffInviteRepository {
  final AuthRepository _firebaseAuth;

  const FirebaseStaffInviteRepository(this._firebaseAuth);

  FirebaseFirestore get _firestore {
    final firestore = _firebaseAuth.activeFirestore;
    if (firestore == null) {
      throw StateError('StaffInviteRepository used with nobody currently signed in.');
    }
    return firestore;
  }

  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection('businesses/$kBusinessId/invites');

  @override
  Future<List<StaffInvite>> pendingInvites() async {
    final snapshot = await _invites.get();
    final invites = snapshot.docs.map(_fromDoc).toList();
    invites.sort((a, b) => b.invitedAt.compareTo(a.invitedAt));
    return invites;
  }

  @override
  Future<void> createInvite({required String email, required String name, required String role}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final invitedBy = _firebaseAuth.currentUser?.uid;
    if (invitedBy == null) {
      throw StateError('createInvite called with nobody currently signed in.');
    }

    final ref = _invites.doc(normalizedEmail);
    // The rules intentionally expose no update path for invites (see
    // firestore.rules) — re-inviting the same email (e.g. fixing a typo
    // in the name, or changing the offered role) is a delete-then-create
    // rather than an edit, so there's never an ambiguous partial state.
    final existing = await ref.get();
    if (existing.exists) {
      await ref.delete();
    }
    await ref.set({
      'name': name.trim(),
      'role': role,
      'invitedAt': FieldValue.serverTimestamp(),
      'invitedBy': invitedBy,
    });
  }

  @override
  Future<void> revokeInvite(String email) async {
    await _invites.doc(email.trim().toLowerCase()).delete();
  }

  StaffInvite _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final invitedAtTimestamp = data['invitedAt'] as Timestamp?;
    return StaffInvite(
      email: doc.id,
      name: data['name'] as String,
      role: data['role'] as String,
      // Falls back to "now" only for the brief window right after
      // createInvite, before the server timestamp round-trips back —
      // never actually persisted this way.
      invitedAt: invitedAtTimestamp?.toDate() ?? DateTime.now(),
      invitedBy: data['invitedBy'] as String,
    );
  }
}
