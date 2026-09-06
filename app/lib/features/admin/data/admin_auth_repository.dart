import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../../auth/data/local_credential_store.dart';

/// The signed-in platform operator — deliberately not [AppUser]: an admin
/// has no role/name/staff doc, isn't scoped to any one business, and
/// isn't a shared-device PIN identity. Just proof of which email signed
/// in, which is all firestore.rules' isPlatformSuperAdmin() cares about
/// (it checks the uid, not anything carried in this object).
class AdminUser {
  final String uid;
  final String email;

  const AdminUser({required this.uid, required this.email});
}

/// Auth for the super-admin onboarding tool ONLY — deliberately NOT
/// AuthRepository/FirebaseAuthRepository. Those exist to solve a
/// completely different problem (multiple staff sharing one till, each
/// with their own cached secondary-FirebaseApp session and a local PIN
/// for the daily fast path). This tool is one person, one browser, used
/// rarely: plain Firebase email-link sign-in against the DEFAULT
/// FirebaseAuth instance, no PIN, no per-user app instance. Session
/// persistence is the Firebase Web SDK's own default
/// (browserLocalPersistence) — nothing extra to build for "stay signed
/// in".
abstract class AdminAuthRepository {
  Stream<AdminUser?> authStateChanges();
  AdminUser? get currentUser;

  bool isSignInWithEmailLink(String link);

  /// Sends the one-time sign-in link and remembers which email it's
  /// pending for (survives a page reload between sending and the admin
  /// tapping the link) — same
  /// [LocalCredentialStore.setPendingVerificationEmail] mechanism the
  /// mobile app's own email-link flow already relies on, reused as-is.
  Future<void> sendSignInLink(String email);

  /// Completes sign-in from the URL the emailed link points at — on web
  /// this is just the same page reopening, no deep-link/App-Links
  /// machinery involved at all.
  Future<void> completeSignInWithLink(String link);

  Future<void> signOut();
}

class FirebaseAdminAuthRepository implements AdminAuthRepository {
  final fb_auth.FirebaseAuth _auth;
  final LocalCredentialStore _store;

  FirebaseAdminAuthRepository({fb_auth.FirebaseAuth? auth, LocalCredentialStore? store})
    : _auth = auth ?? fb_auth.FirebaseAuth.instance,
      _store = store ?? SecureLocalCredentialStore();

  AdminUser? _fromFirebaseUser(fb_auth.User? user) =>
      user == null ? null : AdminUser(uid: user.uid, email: user.email ?? '');

  @override
  Stream<AdminUser?> authStateChanges() => _auth.authStateChanges().map(_fromFirebaseUser);

  @override
  AdminUser? get currentUser => _fromFirebaseUser(_auth.currentUser);

  @override
  bool isSignInWithEmailLink(String link) => _auth.isSignInWithEmailLink(link);

  @override
  Future<void> sendSignInLink(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    await _auth.sendSignInLinkToEmail(
      email: normalizedEmail,
      actionCodeSettings: fb_auth.ActionCodeSettings(
        // Reopens this exact page — a single-page tool with nowhere else
        // the link needs to point. No androidPackageName/iOS bundle id:
        // this is web-only, never meant to hand off to the mobile app.
        url: Uri.base.toString(),
        handleCodeInApp: true,
      ),
    );
    await _store.setPendingVerificationEmail(normalizedEmail);
  }

  @override
  Future<void> completeSignInWithLink(String link) async {
    final pendingEmail = await _store.getPendingVerificationEmail();
    if (pendingEmail == null) {
      throw StateError(
        'No pending admin sign-in email remembered on this browser — the link may have been opened somewhere else, or storage was cleared. Send a new link from this browser.',
      );
    }
    await _auth.signInWithEmailLink(email: pendingEmail, emailLink: link);
    await _store.setPendingVerificationEmail(null);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// In-memory stand-in for tests and the debug entry point. Same
/// broadcast-with-replay shape as FirebaseAuthRepository's own
/// authStateChanges() (a plain StreamController.broadcast(), wrapped in
/// Stream.multi so a new subscriber immediately sees the current value
/// rather than only future changes).
class FakeAdminAuthRepository implements AdminAuthRepository {
  AdminUser? _current;
  String? _pendingEmail;
  String? _pendingLink;
  final _controller = StreamController<AdminUser?>.broadcast();

  @override
  AdminUser? get currentUser => _current;

  @override
  Stream<AdminUser?> authStateChanges() {
    return Stream.multi((controller) {
      controller.add(_current);
      final subscription = _controller.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  bool isSignInWithEmailLink(String link) => link.startsWith('fake-admin-link:');

  @override
  Future<void> sendSignInLink(String email) async {
    _pendingEmail = email.trim().toLowerCase();
    _pendingLink = 'fake-admin-link:${_pendingEmail!}';
  }

  /// Test-only: the fake "emailed" link a test taps, since there's no
  /// real inbox to read from.
  String? get lastSentLink => _pendingLink;

  @override
  Future<void> completeSignInWithLink(String link) async {
    if (_pendingEmail == null) {
      throw StateError('No pending admin sign-in email — call sendSignInLink first.');
    }
    if (link != _pendingLink) {
      throw StateError('That link is invalid or expired.');
    }
    _current = AdminUser(uid: 'fake-admin-uid', email: _pendingEmail!);
    _pendingEmail = null;
    _pendingLink = null;
    _controller.add(_current);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }
}
