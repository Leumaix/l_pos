import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/firebase_auth_repository.dart';
import '../data/firebase_staff_invite_repository.dart';
import '../data/staff_invite_repository.dart';

/// The single, real FirebaseAuthRepository instance — the mobile app's
/// per-staff-secondary-app, email+PIN implementation. Kept as its own
/// provider (rather than folded directly into authRepositoryProvider
/// below) only so lib/main.dart's real wiring and any mobile-specific
/// code can still reach it at its concrete type if ever needed; every
/// OTHER Firebase-backed repository (invites, stock, customers, sales,
/// shift, business, checkout) now depends on activeFirestore via the
/// ABSTRACT AuthRepository instead (see that interface's own doc
/// comment) — that's what lets a web build swap in a completely
/// different AuthRepository implementation (WebAuthRepository — plain
/// default-app email-link sign-in, no PIN, no secondary apps) underneath
/// those same repositories with no changes to them at all.
final firebaseAuthRepositoryProvider = Provider<FirebaseAuthRepository>((ref) => FirebaseAuthRepository());

/// The real, Firebase-backed implementation — this is the "one-line
/// provider change" the fake was always meant to be swapped out for.
/// Widget tests that need a hermetic, fast fake (no real secure-storage
/// or Firebase plumbing) override this provider explicitly with
/// FakeAuthRepository rather than relying on it being the default; see
/// widget_test.dart. The web entry point overrides this provider
/// directly with WebAuthRepository, rather than going through
/// firebaseAuthRepositoryProvider above at all — see lib/main_web.dart.
final authRepositoryProvider = Provider<AuthRepository>((ref) => ref.watch(firebaseAuthRepositoryProvider));

final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Same "one-line swap" pattern as auth: real by default, overridden
/// with FakeStaffInviteRepository in tests.
final staffInviteRepositoryProvider = Provider<StaffInviteRepository>((ref) {
  return FirebaseStaffInviteRepository(ref.watch(authRepositoryProvider));
});
