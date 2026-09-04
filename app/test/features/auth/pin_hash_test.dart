import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/domain/pin_hash.dart';

void main() {
  // Fixed, cheap params for test speed — hashPinWithParams is
  // @visibleForTesting specifically so tests never pay real Argon2id
  // timing while still exercising the real hash/verify/salt logic.
  const salt = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];

  test('a correct PIN verifies against its own hash', () async {
    final hash = await hashPinWithParams('1234', salt: salt);
    expect(await verifyPin('1234', hash), isTrue);
  });

  test('a wrong PIN does not verify', () async {
    final hash = await hashPinWithParams('1234', salt: salt);
    expect(await verifyPin('9999', hash), isFalse);
  });

  test(
    'a near-miss PIN does not verify (not a prefix/substring check)',
    () async {
      final hash = await hashPinWithParams('1234', salt: salt);
      expect(await verifyPin('1235', hash), isFalse);
      expect(await verifyPin('123', hash), isFalse);
      expect(await verifyPin('01234', hash), isFalse);
    },
  );

  test(
    'hashing the same PIN twice with random salts produces different hashes',
    () async {
      final a = await hashPin('1234');
      final b = await hashPin('1234');
      expect(a.hashBase64, isNot(b.hashBase64));
      expect(a.saltBase64, isNot(b.saltBase64));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'verifyPin uses the params stored on the hash, not today\'s defaults',
    () async {
      // A hash made with different (cheaper) params than hashPin()'s
      // current production defaults must still verify correctly — the
      // params travel with the hash specifically so old credentials
      // don't break if defaults are tuned later.
      final hash = await hashPinWithParams(
        '5678',
        salt: salt,
        memoryKiB: 16,
        iterations: 2,
      );
      expect(await verifyPin('5678', hash), isTrue);
    },
  );

  test('PinHash round-trips through JSON', () async {
    final hash = await hashPinWithParams('4321', salt: salt);
    final restored = PinHash.fromJson(hash.toJson());
    expect(await verifyPin('4321', restored), isTrue);
  });
}
