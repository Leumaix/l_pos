import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/domain/pin_lockout.dart';

void main() {
  final now = DateTime(2026, 9, 2, 12, 0);

  group('isLockedOut', () {
    test('a fresh state is never locked', () {
      expect(isLockedOut(const PinLockoutState(), now), isFalse);
    });

    test('locked while now is before lockedUntil', () {
      final state = PinLockoutState(
        failedAttempts: 5,
        lockedUntil: now.add(const Duration(seconds: 10)),
      );
      expect(isLockedOut(state, now), isTrue);
    });

    test('not locked once now reaches lockedUntil', () {
      final state = PinLockoutState(failedAttempts: 5, lockedUntil: now);
      expect(isLockedOut(state, now), isFalse);
    });
  });

  group('recordFailedPinAttempt — escalation', () {
    test('attempts below the minor threshold are just allowed, no lock', () {
      var state = const PinLockoutState();
      for (var i = 1; i < kMinorLockThreshold; i++) {
        final result = recordFailedPinAttempt(state, now);
        expect(result.outcome, PinAttemptOutcome.allowed, reason: 'attempt $i');
        expect(result.newState.lockedUntil, isNull);
        state = result.newState;
      }
      expect(state.failedAttempts, kMinorLockThreshold - 1);
    });

    test('hitting the minor threshold triggers a short lockout', () {
      var state = const PinLockoutState(
        failedAttempts: kMinorLockThreshold - 1,
      );
      final result = recordFailedPinAttempt(state, now);
      expect(result.outcome, PinAttemptOutcome.temporarilyLocked);
      expect(result.newState.lockedUntil, now.add(kMinorLockDuration));
    });

    test('hitting the major threshold triggers a longer lockout', () {
      var state = const PinLockoutState(
        failedAttempts: kMajorLockThreshold - 1,
      );
      final result = recordFailedPinAttempt(state, now);
      expect(result.outcome, PinAttemptOutcome.temporarilyLocked);
      expect(result.newState.lockedUntil, now.add(kMajorLockDuration));
    });

    test('hitting the wipe threshold wipes the credential instead of locking again', () {
      var state = const PinLockoutState(failedAttempts: kWipeThreshold - 1);
      final result = recordFailedPinAttempt(state, now);
      expect(result.outcome, PinAttemptOutcome.credentialWiped);
      // Wiped means back to a clean slate, not a lingering lockout — the
      // caller deletes the whole local credential on this outcome.
      expect(result.newState.failedAttempts, 0);
      expect(result.newState.lockedUntil, isNull);
    });

    test('a full sequence never exceeds the wipe threshold before wiping', () {
      var state = const PinLockoutState();
      PinAttemptOutcome? outcome;
      for (var i = 0; i < kWipeThreshold; i++) {
        final result = recordFailedPinAttempt(state, now);
        outcome = result.outcome;
        state = result.newState;
        if (outcome == PinAttemptOutcome.credentialWiped) break;
      }
      expect(outcome, PinAttemptOutcome.credentialWiped);
    });
  });

  group('resetLockoutState', () {
    test('is always a clean slate regardless of prior failures', () {
      expect(resetLockoutState.failedAttempts, 0);
      expect(resetLockoutState.lockedUntil, isNull);
    });
  });

  group('PinLockoutState JSON round-trip', () {
    test('preserves failedAttempts and lockedUntil', () {
      final state = PinLockoutState(failedAttempts: 3, lockedUntil: now);
      final restored = PinLockoutState.fromJson(state.toJson());
      expect(restored.failedAttempts, 3);
      expect(restored.lockedUntil, now);
    });

    test('preserves a null lockedUntil', () {
      const state = PinLockoutState(failedAttempts: 2);
      final restored = PinLockoutState.fromJson(state.toJson());
      expect(restored.lockedUntil, isNull);
    });
  });
}
