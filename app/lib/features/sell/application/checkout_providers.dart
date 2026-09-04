import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/checkout_repository.dart';

/// Real, Firestore-backed by default — the "one-line swap" this app uses
/// everywhere. Widget tests override this explicitly with a
/// FakeCheckoutRepository built from the same fakes they already use for
/// inventory/customers/sales.
final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => FirebaseCheckoutRepository(ref.watch(firebaseAuthRepositoryProvider)),
);
