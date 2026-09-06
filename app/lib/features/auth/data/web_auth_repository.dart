import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../../../core/business_config.dart';
import 'auth_repository.dart';
import 'local_credential_store.dart';

/// Auth for the web/PWA build ONLY — deliberately NOT FirebaseAuthRepository.
/// That class exists to solve a completely different problem (multiple staff
/// sharing one till, each with their own cached secondary-FirebaseApp session
/// and a local PIN for the daily fast path). On the web, per Sammy's explicit
/// simplification for this first version, every sign-in is a fresh Firebase
/// email-link check against the DEFAULT FirebaseAuth instance — no PIN, no
/// per-staff secondary app, no local device credential store. Session
/// persistence is the Firebase Web SDK's own default
/// (browserLocalPersistence) — nothing extra to build for "stay signed in"
/// across a page reload, same reasoning FirebaseAdminAuthRepository already
/// relies on for the admin tool.
///
/// This implements the FULL AuthRepository interface (so it can sit under
/// the exact same router/screens as FirebaseAuthRepository, unmodified) but
/// the PIN-specific members (isDeviceVerifiedFor, signInWithEmailAndPin,
/// setPinForVerifiedDevice) are never meaningful here — the web build's own
/// login screen never calls them, only sendVerificationLink and
/// completeEmailLinkSignIn. They throw UnsupportedError rather than being
/// silently wrong, so a future caller that reaches them by mistake fails
/// loudly instead of behaving as if a PIN concept existed.
///
/// _loadStaffDoc below is a deliberate, small duplication of
/// FirebaseAuthRepository's own private method of the same shape (same
/// staff-doc lookup + owner-issued-invite self-provisioning logic,
/// firestore.rules independently re-checks the invite/role match either
/// way) rather than an extraction into shared code — FirebaseAuthRepository
/// is the mobile app's already-shipped, already-relied-upon implementation,
/// and this whole feature branch exists specifically to stay sandboxed away
/// from touching that file at all.
class WebAuthRepository implements AuthRepository {
  final fb_auth.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final LocalCredentialStore _store;
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  WebAuthRepository({fb_auth.FirebaseAuth? auth, FirebaseFirestore? firestore, LocalCredentialStore? store})
    : _auth = auth ?? fb_auth.FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance,
      _store = store ?? SecureLocalCredentialStore();

  @override
  AppUser? get currentUser => _currentUser;

  @override
  FirebaseFirestore? get activeFirestore => _currentUser == null ? null : _firestore;

  /// Not part of AuthRepository (the router/other repositories never need
  /// it) — WebAuthController uses this directly, at WebAuthRepository's
  /// own concrete type, to tell an ordinary fresh page load apart from
  /// the browser reopening on a real sign-in link, before ever attempting
  /// completeEmailLinkSignIn. A pure URL-format check, same as
  /// FirebaseAdminAuthRepository's own isSignInWithEmailLink.
  bool isSignInWithEmailLink(String link) => _auth.isSignInWithEmailLink(link);

  @override
  Stream<AppUser?> authStateChanges() {
    return Stream.multi((controller) {
      controller.add(_currentUser);
      final subscription = _controller.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<bool> isDeviceVerifiedFor(String email) {
    throw UnsupportedError(
      'WebAuthRepository has no PIN/device-verification concept — every sign-in is a fresh email link.',
    );
  }

  @override
  Future<AppUser> signInWithEmailAndPin({required String email, required String pin}) {
    throw UnsupportedError(
      'WebAuthRepository has no PIN concept — sign in via sendVerificationLink/completeEmailLinkSignIn instead.',
    );
  }

  @override
  Future<SetPinResult> setPinForVerifiedDevice({required String email, required String pin}) {
    throw UnsupportedError(
      'WebAuthRepository has no PIN concept — completeEmailLinkSignIn already activates the session.',
    );
  }

  @override
  Future<void> sendVerificationLink(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    await _auth.sendSignInLinkToEmail(
      email: normalizedEmail,
      actionCodeSettings: fb_auth.ActionCodeSettings(
        // Reopens this exact page — same reasoning as
        // FirebaseAdminAuthRepository.sendSignInLink: a single-page web
        // app has nowhere else the link needs to point, and Uri.base
        // captures whatever host/port this is actually running on.
        url: Uri.base.toString(),
        handleCodeInApp: true,
      ),
    );
    await _store.setPendingVerificationEmail(normalizedEmail);
  }

  @override
  Future<String?> pendingVerificationEmail() => _store.getPendingVerificationEmail();

  @override
  Future<void> completeEmailLinkSignIn({required String email, required String emailLink}) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!_auth.isSignInWithEmailLink(emailLink)) {
      throw const InvalidCredentialsException();
    }
    final credential = await _auth.signInWithEmailLink(email: normalizedEmail, emailLink: emailLink);
    final fbUser = credential.user;
    if (fbUser == null) {
      throw const InvalidCredentialsException();
    }

    // Real ownership of the email is now proven — necessary, not
    // sufficient, same boundary FirebaseAuthRepository draws: a
    // stranger's own real email still gets a real Firebase Auth account
    // here (email-link sign-in auto-creates one for any address), so
    // _loadStaffDoc is what actually stops them with an honest message
    // instead of a dead end.
    final appUser = await _loadStaffDoc(uid: fbUser.uid, email: normalizedEmail);
    await _store.setPendingVerificationEmail(null);

    // Unlike the mobile flow (verify, THEN separately choose a PIN,
    // THEN activate), there's no PIN step here — completing the email
    // link IS the whole sign-in, so the session activates immediately.
    _currentUser = appUser;
    _controller.add(_currentUser);
  }

  Future<AppUser> _loadStaffDoc({required String uid, required String email}) async {
    final firestore = _firestore;
    final staffRef = firestore.doc('businesses/$kBusinessId/staff/$uid');
    final doc = await staffRef.get();
    final data = doc.data();

    if (doc.exists && data != null && data['active'] == true) {
      return AppUser(
        uid: uid,
        name: data['name'] as String,
        email: email,
        phone: data['phone'] as String?,
        role: data['role'] as String,
      );
    }
    if (doc.exists) {
      // Exists but not active — a deactivated staff member. Self-service
      // provisioning below only ever applies when there's NO staff doc
      // yet; a deactivated one is a deliberate console/owner decision,
      // not something an invite (even a real one) should be able to
      // undo.
      throw const StaffRecordNotFoundException();
    }

    // No staff doc yet — try self-service provisioning via an
    // owner-issued invite (see firestore.rules for the server-side half
    // of this: the create below is independently re-checked there —
    // invite existence and an exact role match — so this client-side
    // lookup only supplies the name/role to WRITE, not the security
    // boundary itself).
    final inviteRef = firestore.doc('businesses/$kBusinessId/invites/$email');
    final inviteDoc = await inviteRef.get();
    final inviteData = inviteDoc.data();
    if (!inviteDoc.exists || inviteData == null) {
      throw const StaffRecordNotFoundException();
    }

    final name = inviteData['name'] as String;
    final role = inviteData['role'] as String;

    // One atomic write: a half-finished attempt (staff doc created but
    // invite still around, or vice versa) must never be observable.
    final batch = firestore.batch();
    batch.set(staffRef, {'name': name, 'role': role, 'active': true});
    batch.delete(inviteRef);
    await batch.commit();

    return AppUser(uid: uid, name: name, email: email, phone: null, role: role);
  }

  @override
  Future<void> signOut() async {
    // Unlike the mobile flow (deactivate the slot but keep the cached
    // Firebase session and local PIN alive for next time — a shared
    // device's daily fast path depends on that), there's no shared
    // device or local credential to preserve here: sign out for real.
    await _auth.signOut();
    _currentUser = null;
    _controller.add(null);
  }
}
