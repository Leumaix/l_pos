import 'pin_hash.dart';
import 'pin_lockout.dart';

/// What this device remembers, locally only, about one staff member who
/// has completed the real email-link verification here: which secondary
/// FirebaseApp instance holds their already-signed-in session, and the
/// salted PIN hash that gates unlocking it. Never leaves the device.
class StaffDeviceCredential {
  final String email;
  final String uid;
  final String appName;
  final PinHash pinHash;
  final PinLockoutState lockout;

  const StaffDeviceCredential({
    required this.email,
    required this.uid,
    required this.appName,
    required this.pinHash,
    this.lockout = const PinLockoutState(),
  });

  StaffDeviceCredential copyWith({PinLockoutState? lockout}) => StaffDeviceCredential(
    email: email,
    uid: uid,
    appName: appName,
    pinHash: pinHash,
    lockout: lockout ?? this.lockout,
  );

  Map<String, dynamic> toJson() => {
    'email': email,
    'uid': uid,
    'appName': appName,
    'pinHash': pinHash.toJson(),
    'lockout': lockout.toJson(),
  };

  factory StaffDeviceCredential.fromJson(Map<String, dynamic> json) => StaffDeviceCredential(
    email: json['email'] as String,
    uid: json['uid'] as String,
    appName: json['appName'] as String,
    pinHash: PinHash.fromJson(json['pinHash'] as Map<String, dynamic>),
    lockout: PinLockoutState.fromJson(json['lockout'] as Map<String, dynamic>),
  );
}
