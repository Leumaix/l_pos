/// How many consecutive wrong PINs before a short local lockout, a longer
/// one, and finally wiping the local credential entirely (forcing a full
/// email-link re-verification). All enforced purely on-device — there is
/// no Firebase call anywhere in this path, so there's nothing here for a
/// remote attacker to even reach.
const kMinorLockThreshold = 5;
const kMinorLockDuration = Duration(seconds: 30);

const kMajorLockThreshold = 10;
const kMajorLockDuration = Duration(minutes: 5);

/// At this many total wrong attempts since the last success, the local
/// credential is wiped rather than locked again — an offline attacker
/// with the device in hand gets nowhere near the full 10,000-PIN space
/// before being forced back through a real email-link verification.
const kWipeThreshold = 15;

class PinLockoutState {
  final int failedAttempts;
  final DateTime? lockedUntil;

  const PinLockoutState({this.failedAttempts = 0, this.lockedUntil});

  Map<String, dynamic> toJson() => {
    'failedAttempts': failedAttempts,
    'lockedUntil': lockedUntil?.toIso8601String(),
  };

  factory PinLockoutState.fromJson(Map<String, dynamic> json) => PinLockoutState(
    failedAttempts: json['failedAttempts'] as int? ?? 0,
    lockedUntil: json['lockedUntil'] == null ? null : DateTime.parse(json['lockedUntil'] as String),
  );
}

enum PinAttemptOutcome { allowed, temporarilyLocked, credentialWiped }

class PinAttemptResult {
  final PinLockoutState newState;
  final PinAttemptOutcome outcome;

  const PinAttemptResult({required this.newState, required this.outcome});
}

bool isLockedOut(PinLockoutState state, DateTime now) {
  final until = state.lockedUntil;
  return until != null && now.isBefore(until);
}

/// The lockout state after a successful PIN entry: always a full reset,
/// regardless of how many failures preceded it.
const PinLockoutState resetLockoutState = PinLockoutState();

/// The lockout state after a WRONG PIN entry. Escalates: a handful of
/// misses is a short cooldown (someone fumbled the keypad), a lot more is
/// a longer one, and enough to meaningfully dent the PIN's search space
/// wipes the credential outright rather than keep locking and unlocking
/// forever.
PinAttemptResult recordFailedPinAttempt(PinLockoutState state, DateTime now) {
  final attempts = state.failedAttempts + 1;

  if (attempts >= kWipeThreshold) {
    return const PinAttemptResult(
      newState: PinLockoutState(),
      outcome: PinAttemptOutcome.credentialWiped,
    );
  }
  if (attempts >= kMajorLockThreshold) {
    return PinAttemptResult(
      newState: PinLockoutState(failedAttempts: attempts, lockedUntil: now.add(kMajorLockDuration)),
      outcome: PinAttemptOutcome.temporarilyLocked,
    );
  }
  if (attempts >= kMinorLockThreshold) {
    return PinAttemptResult(
      newState: PinLockoutState(failedAttempts: attempts, lockedUntil: now.add(kMinorLockDuration)),
      outcome: PinAttemptOutcome.temporarilyLocked,
    );
  }
  return PinAttemptResult(
    newState: PinLockoutState(failedAttempts: attempts),
    outcome: PinAttemptOutcome.allowed,
  );
}
