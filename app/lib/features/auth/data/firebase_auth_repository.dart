import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../../core/business_config.dart';
import '../../../firebase_options.dart';
import '../domain/pin_hash.dart';
import '../domain/pin_lockout.dart';
import '../domain/staff_device_credential.dart';
import 'auth_repository.dart';
import 'local_credential_store.dart';

/// The real implementation. Two Firebase mechanisms compose here, kept
/// deliberately separate:
///
/// 1. A REAL, ONE-TIME Firebase email-link sign-in per staff member per
///    device — proves they own that email, the whole reason this exists.
/// 2. Every sign-in AFTER that, on that same device, is a 4-digit PIN
///    checked ENTIRELY ON-DEVICE (see pin_hash.dart/pin_lockout.dart) —
///    never sent to Firebase, never a Firebase credential of any kind.
///
/// Why not just link an email/password credential (password derived from
/// the PIN) for the daily fast path, the way the original synthetic-email
/// design did? Because that recreates the exact weakness a real one-time
/// verification was meant to close: an email/password pair is a REAL,
/// NETWORK-REACHABLE Firebase credential, attemptable from anywhere in
/// the world, protected by nothing but Firebase's own opaque,
/// volume-tuned rate limiting (confirmed, via Firebase's own security
/// checklist, to be insufficient to rely on for something this narrow — a
/// 4-digit PIN is only 10,000 combinations). The device-binding step
/// would have been security theater if the daily unlock were still a
/// remote credential underneath.
///
/// Instead: Firebase Auth's session persistence on native platforms is
/// automatic and NOT configurable (confirmed against Firebase's own
/// docs) — once signed in, a session stays cached in the OS's secure
/// storage and silently refreshes, no network call needed to "stay signed
/// in". So nothing needs to be invented for that part. What's missing is
/// a LOCAL gate on top of an already-cached session, which is exactly
/// what the PIN is here — verified with a slow, salted Argon2id hash
/// (pin_hash.dart) stored via flutter_secure_storage, with escalating
/// local lockout (pin_lockout.dart). An attacker who wants to guess a PIN
/// now needs the physical device in hand, not just a known email address.
///
/// Multiple staff sharing one till: each gets their OWN secondary
/// FirebaseApp instance (Firebase.initializeApp(name: ..., options: ...)
/// — a real, documented FlutterFire pattern), each independently
/// persisted by the native SDK. "Switching staff" is a purely local
/// operation — which named app's cached session is currently active —
/// never a fresh network credential check.
class FirebaseAuthRepository implements AuthRepository {
  final LocalCredentialStore _store;
  final Map<String, FirebaseApp> _appCache = {};
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  FirebaseAuthRepository({LocalCredentialStore? store})
    : _store = store ?? SecureLocalCredentialStore();

  @override
  AppUser? get currentUser => _currentUser;

  /// The Firestore instance authenticated as whoever is CURRENTLY ACTIVE
  /// on this device — their own secondary FirebaseApp session, so
  /// security rules that check request.auth (isActiveStaffOf,
  /// isActiveOwnerOf) evaluate against the right identity. Null if
  /// nobody's signed in. Other real Firebase-backed repositories
  /// (invites, and eventually stock/customers/sales) read this rather
  /// than touching FirebaseFirestore.instance directly — the DEFAULT
  /// FirebaseApp is never signed in under this design, only the
  /// per-staff secondary apps are.
  @override
  FirebaseFirestore? get activeFirestore {
    final user = _currentUser;
    if (user == null) return null;
    final app = _appCache[_appNameFor(user.email)];
    if (app == null) return null;
    return FirebaseFirestore.instanceFor(app: app);
  }

  @override
  Stream<AppUser?> authStateChanges() {
    return Stream.multi((controller) {
      controller.add(_currentUser);
      final subscription = _controller.stream.listen(controller.add);
      controller.onCancel = subscription.cancel;
    });
  }

  String _appNameFor(String email) {
    final sanitized = email.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '_',
    );
    return 'staff_$sanitized';
  }

  Future<FirebaseApp> _appFor(String appName) async {
    final cached = _appCache[appName];
    if (cached != null) return cached;
    try {
      final existing = Firebase.app(appName);
      _appCache[appName] = existing;
      return existing;
    } on FirebaseException {
      final created = await Firebase.initializeApp(
        name: appName,
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _appCache[appName] = created;
      return created;
    }
  }

  @override
  Future<bool> isDeviceVerifiedFor(String email) async {
    return await _store.get(email) != null;
  }

  @override
  Future<void> sendVerificationLink(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    final app = await _appFor(_appNameFor(normalizedEmail));
    final auth = fb_auth.FirebaseAuth.instanceFor(app: app);

    await auth.sendSignInLinkToEmail(
      email: normalizedEmail,
      actionCodeSettings: fb_auth.ActionCodeSettings(
        // NOT the emailed link's path — Firebase auto-generates that
        // (Hosting domain + /__/auth/links) independent of this value,
        // based on the registered Android app config. This `url` is
        // purely the post-sign-in continueUrl, used only if the web
        // fallback page ever runs. Pointing it AT /__/auth/links itself
        // (a past mistake) broke that fallback: its own JS redirects
        // here on failed app-handoff, landing without the `link=`
        // wrapper its parser requires, and rendering "The operation is
        // not valid." — confirmed by reading the served links.js.
        url: 'https://$kFirebaseHostingDomain/',
        handleCodeInApp: true,
        androidPackageName: kAndroidPackageName,
        androidInstallApp: false,
        // linkDomain deliberately omitted: Firebase auto-uses the
        // project's default Hosting domain, and explicitly setting
        // linkDomain to a DEFAULT domain (web.app/firebaseapp.com) is
        // rejected outright — confirmed against FlutterFire's own docs.
      ),
    );

    await _store.setPendingVerificationEmail(normalizedEmail);
    // Diagnostic only — lets a debug session correlate how long between
    // send and the eventual tap (e.g. to spot a code consumed by an
    // email provider's link-scanner before the real user ever taps it).
    debugPrint(
      'sendVerificationLink: sent at ${DateTime.now().toIso8601String()} for $normalizedEmail',
    );
  }

  @override
  Future<String?> pendingVerificationEmail() =>
      _store.getPendingVerificationEmail();

  @override
  Future<void> completeEmailLinkSignIn({
    required String email,
    required String emailLink,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final app = await _appFor(_appNameFor(normalizedEmail));
    final auth = fb_auth.FirebaseAuth.instanceFor(app: app);

    debugPrint(
      'completeEmailLinkSignIn: attempting at ${DateTime.now().toIso8601String()} for $normalizedEmail\n  link=$emailLink',
    );
    if (!auth.isSignInWithEmailLink(emailLink)) {
      throw const InvalidCredentialsException();
    }
    final credential = await auth.signInWithEmailLink(
      email: normalizedEmail,
      emailLink: emailLink,
    );
    final fbUser = credential.user;
    if (fbUser == null) {
      throw const InvalidCredentialsException();
    }

    // Real ownership of the email is now proven — necessary, not
    // sufficient. A stranger's own real email gets a real Firebase Auth
    // account here too (email-link sign-in auto-creates one for any
    // address); this is what stops them at a clear, honest message
    // instead of letting them proceed to choose a PIN that can never
    // actually be used for anything.
    await _loadStaffDoc(app: app, uid: fbUser.uid, email: normalizedEmail);
    // Deliberately not set as the active session yet — a PIN still needs
    // to be chosen; see setPinForVerifiedDevice.
  }

  @override
  Future<SetPinResult> setPinForVerifiedDevice({
    required String email,
    required String pin,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final appName = _appNameFor(normalizedEmail);
    final app = await _appFor(appName);
    final auth = fb_auth.FirebaseAuth.instanceFor(app: app);
    final fbUser = auth.currentUser;
    if (fbUser == null) {
      throw StateError(
        'setPinForVerifiedDevice called for $normalizedEmail before '
        'completeEmailLinkSignIn succeeded — no signed-in Firebase user '
        'on that app instance.',
      );
    }

    final pinHash = await hashPin(pin);
    final appUser = await _loadStaffDoc(
      app: app,
      uid: fbUser.uid,
      email: normalizedEmail,
    );

    await _store.save(
      StaffDeviceCredential(
        email: normalizedEmail,
        uid: fbUser.uid,
        appName: appName,
        pinHash: pinHash,
      ),
    );
    await _store.setPendingVerificationEmail(null);

    // The tablet is shared, and cart state lives only in memory — auto-
    // switching to the newly-verified person while someone else's shift
    // is already active would silently discard an unsaved, in-progress
    // sale. Only activate if nobody's currently signed in; otherwise the
    // existing session is left exactly as it was, and the new staff
    // member's local credential is saved and ready for their own turn.
    if (_currentUser == null) {
      _currentUser = appUser;
      _controller.add(_currentUser);
      return SetPinResult(staffMember: appUser, activated: true);
    }
    return SetPinResult(
      staffMember: appUser,
      activated: false,
      currentActiveUser: _currentUser,
    );
  }

  @override
  Future<AppUser> signInWithEmailAndPin({
    required String email,
    required String pin,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final credential = await _store.get(normalizedEmail);
    if (credential == null) {
      throw const InvalidCredentialsException();
    }

    final now = DateTime.now();
    if (isLockedOut(credential.lockout, now)) {
      throw PinLockedException(credential.lockout.lockedUntil!);
    }

    final matches = await verifyPin(pin, credential.pinHash);
    if (!matches) {
      final result = recordFailedPinAttempt(credential.lockout, now);

      if (result.outcome == PinAttemptOutcome.credentialWiped) {
        await _store.delete(normalizedEmail);
        throw const DeviceVerificationRequiredException();
      }

      await _store.save(credential.copyWith(lockout: result.newState));

      if (result.outcome == PinAttemptOutcome.temporarilyLocked) {
        throw PinLockedException(result.newState.lockedUntil!);
      }
      throw const InvalidCredentialsException();
    }

    // Correct PIN — reset the lockout state and activate the cached
    // Firebase session. No Firebase call has happened for the PIN check
    // itself; this is the first network-touching step, and it's a plain
    // read using the session the SDK already had cached.
    await _store.save(credential.copyWith(lockout: resetLockoutState));

    final app = await _appFor(credential.appName);
    final auth = fb_auth.FirebaseAuth.instanceFor(app: app);
    final fbUser = auth.currentUser;
    if (fbUser == null) {
      // The cached Firebase session is gone (app data cleared, token
      // revoked, etc.) even though the local PIN credential still
      // existed. Don't silently fail — force back through real
      // verification rather than leaving a dangling local credential
      // that can never actually succeed.
      await _store.delete(normalizedEmail);
      throw const DeviceVerificationRequiredException();
    }

    final appUser = await _loadStaffDoc(
      app: app,
      uid: fbUser.uid,
      email: normalizedEmail,
    );
    _currentUser = appUser;
    _controller.add(_currentUser);
    return appUser;
  }

  Future<AppUser> _loadStaffDoc({
    required FirebaseApp app,
    required String uid,
    required String email,
  }) async {
    final firestore = FirebaseFirestore.instanceFor(app: app);
    final staffRef = firestore.doc('businesses/$kBusinessId/staff/$uid');
    debugPrint('_loadStaffDoc: reading $kBusinessId/staff/$uid');
    final doc = await staffRef.get();
    debugPrint('_loadStaffDoc: staff doc read ok, exists=${doc.exists}');
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
      // yet; a deactivated one is a deliberate console decision, not
      // something an invite (even a real one) should be able to undo.
      throw const StaffRecordNotFoundException();
    }

    // No staff doc yet — try self-service provisioning via an
    // owner-issued invite (see firestore.rules for the server-side half
    // of this: the create below is independently re-checked there —
    // invite existence and an exact role match — so this client-side
    // lookup is what supplies the name/role to WRITE, not the security
    // boundary itself).
    final inviteRef = firestore.doc('businesses/$kBusinessId/invites/$email');
    debugPrint('_loadStaffDoc: reading invite at $kBusinessId/invites/$email');
    final inviteDoc = await inviteRef.get();
    debugPrint('_loadStaffDoc: invite doc read ok, exists=${inviteDoc.exists}');
    final inviteData = inviteDoc.data();
    if (!inviteDoc.exists || inviteData == null) {
      throw const StaffRecordNotFoundException();
    }

    final name = inviteData['name'] as String;
    final role = inviteData['role'] as String;
    final idTokenResult = await fb_auth.FirebaseAuth.instanceFor(app: app)
        .currentUser
        ?.getIdTokenResult();
    debugPrint(
      '_loadStaffDoc: about to batch-commit staff doc for uid=$uid role=$role — '
      'token email=${idTokenResult?.claims?['email']} '
      'email_verified=${idTokenResult?.claims?['email_verified']}',
    );

    // One atomic write: a half-finished attempt (staff doc created but
    // invite still around, or vice versa) must never be observable.
    final batch = firestore.batch();
    batch.set(staffRef, {'name': name, 'role': role, 'active': true});
    batch.delete(inviteRef);
    await batch.commit();
    debugPrint('_loadStaffDoc: batch commit succeeded');

    return AppUser(uid: uid, name: name, email: email, phone: null, role: role);
  }

  @override
  Future<void> signOut() async {
    // Deactivates only the CURRENT slot — deliberately does not call
    // Firebase signOut() or touch the local credential. The cached
    // Firebase session and the local PIN both remain valid for this staff
    // member's next email+PIN entry: ending a shift or switching to a
    // colleague must never force a real re-verification.
    _currentUser = null;
    _controller.add(null);
  }
}
