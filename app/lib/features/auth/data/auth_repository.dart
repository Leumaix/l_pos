import 'package:cloud_firestore/cloud_firestore.dart';

/// The signed-in staff member, as far as the rest of the app needs to know.
/// [phone] is contact info only now — it plays no role in sign-in (see
/// [AuthRepository] doc).
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String? phone;
  final String role;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
  });
}

/// Thrown when an email+PIN combination doesn't match a provisioned staff
/// account, or the PIN is simply wrong. Staff accounts are provisioned
/// out-of-band (see project notes), not created from within the app —
/// there is no self-service sign-up.
class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException();
}

/// Thrown when the on-device PIN check is temporarily locked out after too
/// many wrong attempts — purely local, nothing to do with Firebase.
class PinLockedException implements Exception {
  final DateTime lockedUntil;
  const PinLockedException(this.lockedUntil);
}

/// Thrown when this device either never completed email-link verification
/// for the given email, or its local credential was just wiped (too many
/// wrong PIN attempts) — either way, the only way forward is the real
/// one-time email-link flow again.
class DeviceVerificationRequiredException implements Exception {
  const DeviceVerificationRequiredException();
}

/// Thrown when real ownership of an email was just proven (a completed
/// email-link sign-in, or a matching local PIN) but there's no ACTIVE
/// staff record for that account under this business — a stranger who
/// entered their own real email (email-link sign-in auto-creates a
/// Firebase Auth account for any address, registered or not), or a former
/// staff member who's been deactivated. Proving email ownership is
/// necessary but never sufficient; the Firestore security rules
/// (`isActiveStaffOf`) are the real, server-side gate on data access
/// either way — this exists purely so the person sees an honest message
/// instead of a dead end or a misleading one.
class StaffRecordNotFoundException implements Exception {
  const StaffRecordNotFoundException();
}

/// Thrown by [AuthRepository.verifyActiveOwnerPin] when the PIN itself was
/// correct but that staff member isn't currently an active owner (wrong
/// role, deactivated, or the staff record is gone) — a distinct case from
/// [StaffRecordNotFoundException], which covers email-link sign-in; this
/// one is specifically "the PIN check passed, but this isn't a valid
/// owner-approval signature."
class NotAnActiveOwnerException implements Exception {
  const NotAnActiveOwnerException();
}

/// Outcome of [AuthRepository.setPinForVerifiedDevice]. [staffMember] is
/// always the person who just finished setup; [activated] says whether
/// their session became this app's active one. When it didn't (someone
/// else was already signed in on this shared device), [currentActiveUser]
/// names who — for a "setup complete, ask them to sign out" message.
class SetPinResult {
  final AppUser staffMember;
  final bool activated;
  final AppUser? currentActiveUser;

  const SetPinResult({
    required this.staffMember,
    required this.activated,
    this.currentActiveUser,
  });
}

/// Auth is email + 4-digit PIN — not phone + PIN. A staff member's very
/// first sign-in on any device completes a real Firebase email-link
/// verification (one genuine email sent, opened on the same device); every
/// sign-in after that, on that SAME device, is a 4-digit PIN checked
/// entirely on-device against a locally stored salted hash — never a
/// Firebase network call. See the concrete Firebase implementation's doc
/// comment for why: the daily PIN must never become a remotely-guessable
/// Firebase credential, which an email/password-linked PIN would have
/// been.
///
/// This was phone + SMS OTP originally; switched to email + link because
/// real Firebase Phone Auth SMS sending now requires a linked Blaze billing
/// account with no way around it, while email-link sign-in stays fully
/// free on Spark. Phone stays on the staff record for contact purposes
/// only, not sign-in.
abstract class AuthRepository {
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  /// The Firestore instance authenticated as whoever is CURRENTLY ACTIVE,
  /// null if nobody's signed in — every other real Firebase-backed
  /// repository (invites, stock, customers, sales, shift, business,
  /// checkout) reads this rather than touching FirebaseFirestore.instance
  /// directly, so security rules that check request.auth evaluate against
  /// the right identity regardless of which concrete AuthRepository is
  /// wired up (FirebaseAuthRepository's per-staff secondary-app session
  /// for mobile, or a plain default-app session for web — see
  /// WebAuthRepository).
  FirebaseFirestore? get activeFirestore;

  /// True if this device already has a local credential for [email] —
  /// lets the UI decide whether to show the PIN keypad or the "verify by
  /// email" prompt, without attempting a sign-in first.
  Future<bool> isDeviceVerifiedFor(String email);

  /// The fast path: checks [pin] entirely on-device against the local
  /// credential for [email]. Throws [InvalidCredentialsException] if
  /// there's no local credential or the PIN is wrong,
  /// [PinLockedException] if too many recent wrong attempts have
  /// triggered a local cooldown, or [DeviceVerificationRequiredException]
  /// if this attempt was the one that wiped the credential (too many
  /// wrong attempts total) or the cached Firebase session is no longer
  /// valid.
  Future<AppUser> signInWithEmailAndPin({required String email, required String pin});

  /// Starts one-time device verification: sends a real Firebase sign-in
  /// link to [email]. Completion happens later, out-of-band, when the
  /// link is opened on this device (see [completeEmailLinkSignIn]).
  Future<void> sendVerificationLink(String email);

  /// The email a verification link was most recently sent to and not yet
  /// completed — survives the app closing between send and the staff
  /// member tapping the link, so a cold start via the deep link still
  /// knows whose verification this is.
  Future<String?> pendingVerificationEmail();

  /// Call when the app is opened via the email-link deep link. Completes
  /// the real Firebase verification for [email] using [emailLink] (the
  /// full incoming URI as a string), then immediately checks for an
  /// active staff record — throwing [StaffRecordNotFoundException] rather
  /// than letting a stranger proceed to choose a PIN. The signed-in
  /// Firebase session isn't this app's ACTIVE session yet —
  /// [setPinForVerifiedDevice] finishes the job once a PIN has been
  /// chosen.
  Future<void> completeEmailLinkSignIn({required String email, required String emailLink});

  /// Finishes first-time device setup: hashes and locally stores [pin]
  /// for the just-verified [email]. Only makes that staff member's
  /// session the ACTIVE one if nobody is currently signed in on this
  /// device (see [SetPinResult.activated]) — the tablet is shared, and
  /// auto-switching away from another staff member's in-progress,
  /// unsaved sale would silently discard it. Throws
  /// [StaffRecordNotFoundException] if the staff record disappeared
  /// between email verification and now.
  Future<SetPinResult> setPinForVerifiedDevice({required String email, required String pin});

  /// Verifies [pin] against the LOCAL credential for [email] — same
  /// local-only checks [signInWithEmailAndPin] already does (a stored
  /// credential exists, isn't locked out, the PIN hash matches) — but
  /// NEVER touches the active session: [currentUser] and
  /// [authStateChanges] are completely unaffected, on success or
  /// failure. On success, additionally confirms — via one Firestore
  /// read performed as THAT email's own cached session, never the
  /// caller's active one — that they're currently an active staff
  /// member with role 'owner', throwing [NotAnActiveOwnerException] if
  /// not. Built for exactly one purpose: a shared-device "the owner
  /// needs to approve this right now" moment (see the gifting feature)
  /// where whoever is currently signed in must stay signed in
  /// regardless of the outcome. Returns that owner's uid on success —
  /// callers writing something as their own session (via
  /// [firestoreForEmail]) need it to attribute the write. Throws
  /// [InvalidCredentialsException] / [PinLockedException] /
  /// [DeviceVerificationRequiredException] with the same meanings as
  /// [signInWithEmailAndPin].
  Future<String> verifyActiveOwnerPin({required String email, required String pin});

  /// The authenticated Firestore instance for [email]'s own cached
  /// session — meaningful only immediately after
  /// [verifyActiveOwnerPin] has just succeeded for that same email.
  /// Lets a caller perform ONE write as that specific person's own
  /// genuine session (so a security rule's request.auth.uid check is
  /// real, not a client-side PIN check that was verified and then
  /// discarded) without ever switching who's active. Null if that
  /// email has no cached session at all.
  FirebaseFirestore? firestoreForEmail(String email);

  /// Deactivates the current session (returns to Login) WITHOUT touching
  /// the underlying Firebase session or the local PIN credential — the
  /// whole point of the local-PIN design is that ending a shift or
  /// switching staff never forces anyone back through real verification.
  /// See the Firebase implementation's doc comment.
  Future<void> signOut();
}
