import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/firebase_auth_repository.dart';
import '../data/firebase_staff_invite_repository.dart';
import '../data/staff_invite_repository.dart';

/// The single, real FirebaseAuthRepository instance. Exposed at its
/// concrete type (not just the abstract AuthRepository) so OTHER real
/// Firebase-backed repositories (invites today; stock/customers/sales
/// eventually) can reach FirebaseAuthRepository.activeFirestore — the
/// currently active staff member's authenticated Firestore session,
/// which is what Firestore rules actually check.
final firebaseAuthRepositoryProvider = Provider<FirebaseAuthRepository>((ref) => FirebaseAuthRepository());

/// The real, Firebase-backed implementation — this is the "one-line
/// provider change" the fake was always meant to be swapped out for.
/// Widget tests that need a hermetic, fast fake (no real secure-storage
/// or Firebase plumbing) override this provider explicitly with
/// FakeAuthRepository rather than relying on it being the default; see
/// widget_test.dart.
final authRepositoryProvider = Provider<AuthRepository>((ref) => ref.watch(firebaseAuthRepositoryProvider));

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Same "one-line swap" pattern as auth: real by default, overridden
/// with FakeStaffInviteRepository in tests.
final staffInviteRepositoryProvider = Provider<StaffInviteRepository>((ref) {
  return FirebaseStaffInviteRepository(ref.watch(firebaseAuthRepositoryProvider));
});
