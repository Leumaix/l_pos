import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/staff_device_credential.dart';

/// Where a device's local staff credentials live — one entry per staff
/// member who has completed the real email-link verification on THIS
/// device. Never synced anywhere; a fresh install or cleared app data
/// means everyone on that device has to re-verify.
abstract class LocalCredentialStore {
  Future<StaffDeviceCredential?> get(String email);
  Future<void> save(StaffDeviceCredential credential);
  Future<void> delete(String email);

  /// The email a "send verification link" is currently pending for —
  /// survives the app closing between sending the link and the staff
  /// member tapping it, so the deep-link handler knows which email the
  /// incoming link belongs to.
  Future<String?> getPendingVerificationEmail();
  Future<void> setPendingVerificationEmail(String? email);
}

class SecureLocalCredentialStore implements LocalCredentialStore {
  final FlutterSecureStorage _storage;

  SecureLocalCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _pendingEmailKey = 'leumadepos.pending_verification_email';

  String _keyFor(String email) => 'leumadepos.staff_credential.${email.trim().toLowerCase()}';

  @override
  Future<StaffDeviceCredential?> get(String email) async {
    final raw = await _storage.read(key: _keyFor(email));
    if (raw == null) return null;
    return StaffDeviceCredential.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(StaffDeviceCredential credential) async {
    await _storage.write(key: _keyFor(credential.email), value: jsonEncode(credential.toJson()));
  }

  @override
  Future<void> delete(String email) async {
    await _storage.delete(key: _keyFor(email));
  }

  @override
  Future<String?> getPendingVerificationEmail() => _storage.read(key: _pendingEmailKey);

  @override
  Future<void> setPendingVerificationEmail(String? email) async {
    if (email == null) {
      await _storage.delete(key: _pendingEmailKey);
    } else {
      await _storage.write(key: _pendingEmailKey, value: email);
    }
  }
}

/// In-memory stand-in, for tests that exercise FirebaseAuthRepository's
/// logic without pulling in the real secure-storage platform plugin.
class InMemoryCredentialStore implements LocalCredentialStore {
  final Map<String, StaffDeviceCredential> _entries = {};
  String? _pendingEmail;

  String _key(String email) => email.trim().toLowerCase();

  @override
  Future<StaffDeviceCredential?> get(String email) async => _entries[_key(email)];

  @override
  Future<void> save(StaffDeviceCredential credential) async {
    _entries[_key(credential.email)] = credential;
  }

  @override
  Future<void> delete(String email) async {
    _entries.remove(_key(email));
  }

  @override
  Future<String?> getPendingVerificationEmail() async => _pendingEmail;

  @override
  Future<void> setPendingVerificationEmail(String? email) async {
    _pendingEmail = email;
  }
}
