import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// A PIN's hash, salt, and the exact Argon2id parameters used to produce
/// it — stored, never the PIN itself. Parameters travel with the hash (not
/// hardcoded separately) so they can be tuned later without invalidating
/// already-stored credentials from before the change.
class PinHash {
  final String saltBase64;
  final String hashBase64;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  const PinHash({
    required this.saltBase64,
    required this.hashBase64,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  Map<String, dynamic> toJson() => {
    'saltBase64': saltBase64,
    'hashBase64': hashBase64,
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
  };

  factory PinHash.fromJson(Map<String, dynamic> json) => PinHash(
    saltBase64: json['saltBase64'] as String,
    hashBase64: json['hashBase64'] as String,
    memoryKiB: json['memoryKiB'] as int,
    iterations: json['iterations'] as int,
    parallelism: json['parallelism'] as int,
  );
}

// Argon2id parameters for hashing a staff PIN. Deliberately not the OWASP
// "interactive login" minimum (19 MiB) — a 4-digit PIN's entire search
// space is 10,000 values, so hashing needs to be slow enough that even an
// offline attacker with the device's secure storage extracted can't burn
// through all 10,000 quickly. 64 MiB / 3 iterations costs a fraction of a
// second on a phone-class CPU per attempt (fine for the one legitimate
// unlock) but meaningfully taxes an offline brute force — combined with
// the local lockout in pin_lockout.dart, which caps attempts far below
// 10,000 before forcing a full re-verification anyway.
const _memoryKiB = 65536; // 64 MiB
const _iterations = 3;
const _parallelism = 1; // mobile CPUs; higher parallelism buys little here
const _saltLength = 16;
const _hashLength = 32;

Argon2id _algorithm({required int memoryKiB, required int iterations, required int parallelism}) {
  return Argon2id(
    memory: memoryKiB,
    iterations: iterations,
    parallelism: parallelism,
    hashLength: _hashLength,
  );
}

List<int> _randomSalt() {
  final random = Random.secure();
  return List<int>.generate(_saltLength, (_) => random.nextInt(256));
}

/// Hashes [pin] with a freshly generated random salt, using the current
/// parameters. Never call this with a fixed/testing salt outside tests.
Future<PinHash> hashPin(String pin) async {
  final salt = _randomSalt();
  final algorithm = _algorithm(memoryKiB: _memoryKiB, iterations: _iterations, parallelism: _parallelism);
  final secretKey = await algorithm.deriveKeyFromPassword(password: pin, nonce: salt);
  final bytes = await secretKey.extractBytes();
  return PinHash(
    saltBase64: base64Encode(salt),
    hashBase64: base64Encode(bytes),
    memoryKiB: _memoryKiB,
    iterations: _iterations,
    parallelism: _parallelism,
  );
}

/// Verifies [pin] against a previously stored [stored] hash — recomputes
/// with the SAME salt and parameters the hash was created with (not
/// today's defaults, in case they change later) and compares in constant
/// time.
Future<bool> verifyPin(String pin, PinHash stored) async {
  final salt = base64Decode(stored.saltBase64);
  final algorithm = _algorithm(
    memoryKiB: stored.memoryKiB,
    iterations: stored.iterations,
    parallelism: stored.parallelism,
  );
  final secretKey = await algorithm.deriveKeyFromPassword(password: pin, nonce: salt);
  final candidate = await secretKey.extractBytes();
  final expected = base64Decode(stored.hashBase64);
  return _constantTimeEquals(candidate, expected);
}

/// Byte comparison that takes the same time regardless of where the
/// mismatch is, so a timing side-channel can't leak how many leading
/// bytes of a guess were correct. Different LENGTHS still short-circuit
/// (never true for a fixed-length hash, and length isn't secret).
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Exposed for tests only, so tests don't wait on real Argon2id timing
/// while still exercising the real hash/verify/salt logic.
@visibleForTesting
Future<PinHash> hashPinWithParams(
  String pin, {
  required List<int> salt,
  int memoryKiB = 8,
  int iterations = 1,
  int parallelism = 1,
}) async {
  final algorithm = _algorithm(memoryKiB: memoryKiB, iterations: iterations, parallelism: parallelism);
  final secretKey = await algorithm.deriveKeyFromPassword(password: pin, nonce: salt);
  final bytes = await secretKey.extractBytes();
  return PinHash(
    saltBase64: base64Encode(salt),
    hashBase64: base64Encode(bytes),
    memoryKiB: memoryKiB,
    iterations: iterations,
    parallelism: parallelism,
  );
}
