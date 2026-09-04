import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/business_config.dart';
import '../../auth/application/auth_providers.dart';
import '../data/business_repository.dart';
import '../data/firebase_business_repository.dart';

/// The signed-in staff member's business — shown on the dashboard header
/// and receipts. A plain constant for now; becomes a Firestore read
/// (businesses/{businessId}.name) once that's wired up. Leumadepos itself
/// is multi-tenant-ready, but this one install is configured for
/// PH-Zazaa Oil & Gas.
final businessNameProvider = Provider<String>((ref) => 'PH-Zazaa Oil & Gas');

/// Same "one-line swap" pattern as auth/invites: real by default,
/// overridden with FakeBusinessRepository in tests.
final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  return FirebaseBusinessRepository(ref.watch(firebaseAuthRepositoryProvider));
});

final _gasTankCapacityStreamProvider = StreamProvider<double>((ref) {
  return ref.watch(businessRepositoryProvider).watchGasTankCapacityKg();
});

/// Same contract Stock/Reports already relied on (a plain double, not
/// async) so neither screen needs to change how it reads this — now
/// backed by a live Firestore stream instead of a hardcoded placeholder,
/// with [kDefaultGasTankCapacityKg] covering the brief initial-load
/// window and any read error.
final gasTankCapacityKgProvider = Provider<double>((ref) {
  return ref.watch(_gasTankCapacityStreamProvider).valueOrNull ?? kDefaultGasTankCapacityKg;
});
