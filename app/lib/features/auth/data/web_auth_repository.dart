import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../../../core/business_config.dart';
import 'auth_repository.dart';

/// Thrown by [WebAuthRepository.completeSignUp] when the staff member
/// says they've clicked the verification link but Firebase's own record
/// (reloaded fresh — emailVerified doesn't update locally on its own)
/// still shows unverified. Distinct from [StaffRecordNotFoundException]:
/// this is "not proven yet", not "proven but not authorized".
class EmailNotVerifiedException implements Exception {
  const EmailNotVerifiedException();
}

/// Auth for the web/PWA build ONLY — deliberately NOT FirebaseAuthRepository.
/// That class exists to solve a completely different problem (multiple staff
/// sharing one till, each with their own cached secondary-FirebaseApp session
/// and a local PIN for the daily fast path). On the web, every sign-in is
/// against the DEFAULT FirebaseAuth instance — no PIN, no per-staff
/// secondary app.
///
/// Originally built as plain passwordless email-link sign-in, matching the
/// mobile app's first-time verification step. Switched to email+password
/// because email-link requires sending a real email on every single login,
/// which kept exhausting Firebase's daily sign-in-email quota during normal
/// use and testing. Now: sign-up (once) still proves email ownership via a
/// real email — Firebase's own address-verification link, sent exactly
/// once per new staff member, never per login — but every login after that
/// is plain email+password, zero emails sent.
///
/// This implements the FULL AuthRepository interface (so it can sit under
/// the exact same router/screens as FirebaseAuthRepository, unmodified) but
/// none of its members actually describe this flow anymore — PIN-specific
/// (isDeviceVerifiedFor, signInWithEmailAndPin, setPinForVerifiedDevice)
/// and email-link-specific (sendVerificationLink, pendingVerificationEmail,
/// completeEmailLinkSignIn) all throw UnsupportedError rather than being
/// silently wrong. The web build's own screens call signUp/completeSignUp/
/// signIn directly, at this class's own concrete type — same reasoning as
/// before: this controller is inherently web-only and will never need
/// swapping to a different AuthRepository implementation.
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
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  /// Resolves once Firebase Auth has finished restoring (or confirmed
  /// there's nothing to restore) whatever session IndexedDB had for this
  /// browser profile. `_auth.currentUser` is a synchronous getter that
  /// reads whatever's in memory RIGHT NOW — on a fresh page load that
  /// restore is still an in-flight async read, so checking currentUser
  /// (or [pendingSignUpUser], which reads it) before this resolves sees
  /// null even when a real persisted session exists. Confirmed live
  /// against the Auth emulator: the session genuinely was still sitting
  /// in IndexedDB at reload (read directly, byte for byte, before the
  /// app's own boot sequence ran), yet checking currentUser synchronously
  /// at startup — resume logic previously ran immediately at
  /// WebAuthController construction — read null and fell through to a
  /// blank login form. [authStateChanges]'s first emission fires exactly
  /// once that restore (or its absence) is settled, whichever it is.
  late final Future<void> _authReady = _auth.authStateChanges().first;

  /// See [_authReady] — call sites that read [currentUser] or
  /// [pendingSignUpUser] right at app boot must await this first.
  Future<void> get authReady => _authReady;

  /// Deliberately does NOT call `_auth.setPersistence(...)` here, even
  /// though an earlier version of this class did, "explicitly", to pin
  /// down browserLocalPersistence (already the SDK's own default).
  /// That explicit call turned out to be actively harmful: confirmed via
  /// a real Auth-emulator close/reopen test that a signed-in session
  /// never survived a browser restart, root-caused to a documented
  /// firebase-js-sdk bug — setPersistence(browserLocalPersistence) is
  /// NOT idempotent and wipes any already-persisted session on every
  /// call, including a call that just re-confirms the current (default)
  /// mode. Since this constructor runs on every fresh app load —
  /// including the reload after a real close/reopen — calling it here
  /// was wiping out the very session it claimed to be preserving. The
  /// SDK's own default already IS browserLocalPersistence with no call
  /// needed at all.
  WebAuthRepository({fb_auth.FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? fb_auth.FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  FirebaseFirestore? get activeFirestore =>
      _currentUser == null ? null : _firestore;

  /// A Firebase-authenticated user who hasn't finished sign-up yet —
  /// account created, but not yet self-provisioned as a real staff
  /// member (either still unverified, or verified but completeSignUp
  /// hasn't run). Lets WebAuthController resume the right screen after
  /// a page reload mid-signup instead of losing all progress back to a
  /// blank form — Firebase's own default session persistence already
  /// keeps this cached across a reload on its own, no extra local
  /// storage needed here.
  fb_auth.User? get pendingSignUpUser =>
      _currentUser == null ? _auth.currentUser : null;

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
      'WebAuthRepository has no PIN/device-verification concept — sign in with signIn(email, password) instead.',
    );
  }

  @override
  Future<AppUser> signInWithEmailAndPin({
    required String email,
    required String pin,
  }) {
    throw UnsupportedError(
      'WebAuthRepository has no PIN concept — use signIn(email, password) instead.',
    );
  }

  @override
  Future<SetPinResult> setPinForVerifiedDevice({
    required String email,
    required String pin,
  }) {
    throw UnsupportedError(
      'WebAuthRepository has no PIN concept — completeSignUp already activates the session.',
    );
  }

  @override
  Future<void> sendVerificationLink(String email) {
    throw UnsupportedError(
      'WebAuthRepository no longer uses email-link sign-in — use signUp(email, password).',
    );
  }

  @override
  Future<String?> pendingVerificationEmail() {
    throw UnsupportedError(
      'WebAuthRepository no longer uses email-link sign-in — use pendingSignUpUser instead.',
    );
  }

  @override
  Future<void> completeEmailLinkSignIn({
    required String email,
    required String emailLink,
  }) {
    throw UnsupportedError(
      'WebAuthRepository no longer uses email-link sign-in — use completeSignUp() after email verification.',
    );
  }

  /// Stage 1 of sign-up: creates the Firebase Auth account and sends the
  /// one-time address-verification email — the ONLY email this flow ever
  /// sends, and only once per new staff member, never on a later login.
  /// Deliberately does NOT touch self-provisioning or activate a session
  /// yet — see [completeSignUp].
  Future<void> signUp({required String email, required String password}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    await credential.user?.sendEmailVerification();
  }

  /// Re-sends the same one-time verification email — for "I didn't get
  /// it" on the awaiting-verification screen. Not a new account, not an
  /// additional email budget concern beyond the one this specific staff
  /// member's sign-up already accounts for.
  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError(
        'resendVerificationEmail called with nobody signed in — call signUp first.',
      );
    }
    await user.sendEmailVerification();
  }

  /// Stage 2 of sign-up: call once the staff member says they've clicked
  /// the verification link. Reloads the cached Firebase user first —
  /// emailVerified never updates locally on its own — and only once
  /// that genuinely shows true does this proceed. Deliberately a
  /// separate, later step from [signUp], not fused into one call: a
  /// future payment/subscription gate can be inserted right here,
  /// between "ownership proven" (already true by the time this method
  /// is even worth calling) and "staff doc actually created"
  /// (self-provisioning, below) — without touching the invite-
  /// consumption logic at all when that day comes.
  Future<AppUser> completeSignUp() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError(
        'completeSignUp called with nobody signed in — call signUp first.',
      );
    }
    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed == null || !refreshed.emailVerified) {
      throw const EmailNotVerifiedException();
    }
    // reload() only updates the LOCAL User object's own emailVerified
    // field — it does NOT refresh the cached ID token, and
    // firestore.rules' request.auth.token.email_verified reads that
    // token's own claim, not this local field. Without forcing a new
    // token here, the self-provisioning write below gets rejected with
    // a genuine permission-denied even though emailVerified just read
    // true — caught live against the real rules (not a mocked test),
    // driving the sign-up flow through a real Auth+Firestore emulator
    // pair end to end.
    await refreshed.getIdToken(true);
    final email = refreshed.email;
    if (email == null) {
      throw StateError(
        'completeSignUp: the Firebase user has no email — should be impossible for password sign-up.',
      );
    }

    // <-- a future payment/subscription check belongs here: ownership is
    // already proven at this point, but self-provisioning (below) hasn't
    // happened yet.

    final appUser = await _loadStaffDoc(uid: refreshed.uid, email: email);
    _currentUser = appUser;
    _controller.add(_currentUser);
    return appUser;
  }

  /// Every login after sign-up: plain email + password, no email sent.
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final credential = await _auth.signInWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final fbUser = credential.user;
    if (fbUser == null) {
      throw const InvalidCredentialsException();
    }

    final appUser = await _loadStaffDoc(
      uid: fbUser.uid,
      email: normalizedEmail,
    );
    _currentUser = appUser;
    _controller.add(_currentUser);
    return appUser;
  }

  Future<AppUser> _loadStaffDoc({
    required String uid,
    required String email,
  }) async {
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
    // invite existence, email_verified, and an exact role match — so
    // this client-side lookup only supplies the name/role to WRITE, not
    // the security boundary itself).
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
