import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/business_config.dart';
import '../../auth/data/auth_repository.dart';
import 'business_repository.dart';

/// Real implementation — reads/writes through whoever is CURRENTLY
/// ACTIVE's authenticated Firestore session (see
/// FirebaseAuthRepository.activeFirestore), since that's the identity
/// Firestore rules check. The business doc's settings don't vary by
/// viewer, so which staff member's session happens to back this read
/// doesn't matter — only that they're a valid active staff member.
class FirebaseBusinessRepository implements BusinessRepository {
  final AuthRepository _firebaseAuth;

  const FirebaseBusinessRepository(this._firebaseAuth);

  FirebaseFirestore get _firestore {
    final firestore = _firebaseAuth.activeFirestore;
    if (firestore == null) {
      throw StateError('BusinessRepository used with nobody currently signed in.');
    }
    return firestore;
  }

  @override
  Stream<double> watchGasTankCapacityKg() {
    return _firestore.doc('businesses/$kBusinessId').snapshots().map((doc) {
      final settings = doc.data()?['settings'] as Map<String, dynamic>?;
      final capacity = settings?['gasTankCapacityKg'];
      if (capacity == null) return kDefaultGasTankCapacityKg;
      return (capacity as num).toDouble();
    });
  }

  @override
  Future<void> updateGasTankCapacityKg(double capacityKg) async {
    // A dotted-path update touches only this one nested field — never
    // rewrites the whole document — matching exactly what
    // firestore.rules independently checks changed.
    await _firestore.doc('businesses/$kBusinessId').update({
      'settings.gasTankCapacityKg': capacityKg,
    });
  }
}
