import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_repository.dart';

/// Stand-in for the real Firebase-backed implementation, used until the
/// Firebase project is wired up — and still useful for tests/dev flows
/// that don't need real email-link mechanics. Accepts a fixed set of
/// seeded staff so the Login screen and everything downstream of it can
/// be built and clicked through end-to-end without real Firebase.
///
/// The first-time-verification methods here are trivial no-op stand-ins:
/// every seeded email is treated as already "device-verified", so this
/// fake never exercises the real email-link flow — that's
/// FirebaseAuthRepository's job.
///
/// Seeded staff: chidi@leumadepos.test / PIN "1234" (owner),
/// ifeoma@leumadepos.test / PIN "1111" (attendant).
class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  static const _seeded = <String, ({String pin, AppUser user})>{
    'chidi@leumadepos.test': (
      pin: '1234',
      user: AppUser(
        uid: 'seed-owner',
        name: 'Chidi (Owner)',
        email: 'chidi@leumadepos.test',
        phone: '08030000000',
        role: 'owner',
      ),
    ),
    'ifeoma@leumadepos.test': (
      pin: '1111',
      user: AppUser(
        uid: 'seed-attendant',
        name: 'Ifeoma',
        email: 'ifeoma@leumadepos.test',
        phone: '08030000001',
        role: 'attendant',
      ),
    ),
  };

  @override
  AppUser? get currentUser => _currentUser;

  /// This fake never touches real Firestore — nothing in the widget-test
  /// suite exercises a real Firebase-backed repository alongside this
  /// fake, so there's no real session to hand back here.
  @override
  FirebaseFirestore? get activeFirestore => null;

  @override
  Stream<AppUser?> authStateChanges() {
    // Mirrors real Firebase Auth semantics: every new listener gets the
    // current state immediately, then subsequent changes — not just
    // listeners that happened to already be subscribed when a change
    // occurred (a plain broadcast stream doesn't replay past events).
    return Stream.multi((controller) {
      controller.add(_currentUser);
      final subscription = _controller.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  /// Test-only: re-emits the current user as a brand-new AppUser
  /// instance with identical fields — simulating a real Firebase
  /// authStateChanges() redundant emission (e.g. a token refresh),
  /// which is a genuinely distinct object even though nothing about the
  /// signed-in user actually changed. AppUser has no == override, so
  /// this is "different" by identity to anything watching the provider
  /// directly; a listener that should be resilient to that (e.g.
  /// AppShell's isOwner, via .select) needs exactly this kind of case
  /// covered — see app_shell_test.dart.
  void debugReemitCurrentUser() {
    final user = _currentUser;
    if (user != null) {
      _controller.add(
        AppUser(uid: user.uid, name: user.name, email: user.email, phone: user.phone, role: user.role),
      );
    }
  }

  @override
  Future<bool> isDeviceVerifiedFor(String email) async {
    return _seeded.containsKey(email.trim().toLowerCase());
  }

  @override
  Future<AppUser> signInWithEmailAndPin({required String email, required String pin}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final seed = _seeded[email.trim().toLowerCase()];
    if (seed == null || seed.pin != pin) {
      throw const InvalidCredentialsException();
    }

    _currentUser = seed.user;
    _controller.add(_currentUser);
    return seed.user;
  }

  String? _pendingEmail;

  @override
  Future<void> sendVerificationLink(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _pendingEmail = email.trim().toLowerCase();
  }

  @override
  Future<String?> pendingVerificationEmail() async => _pendingEmail;

  @override
  Future<void> completeEmailLinkSignIn({required String email, required String emailLink}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!_seeded.containsKey(email.trim().toLowerCase())) {
      throw const StaffRecordNotFoundException();
    }
  }

  @override
  Future<SetPinResult> setPinForVerifiedDevice({required String email, required String pin}) async {
    final seed = _seeded[email.trim().toLowerCase()];
    if (seed == null) throw const StaffRecordNotFoundException();

    if (_currentUser == null) {
      _currentUser = seed.user;
      _controller.add(_currentUser);
      return SetPinResult(staffMember: seed.user, activated: true);
    }
    return SetPinResult(staffMember: seed.user, activated: false, currentActiveUser: _currentUser);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }
}
