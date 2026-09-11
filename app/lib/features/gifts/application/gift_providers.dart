import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/gift_repository.dart';

/// Same "one-line swap" pattern as checkout/expenses/shift: real by
/// default, overridden with FakeGiftRepository in tests.
final giftRepositoryProvider = Provider<GiftRepository>(
  (ref) => FirebaseGiftRepository(ref.watch(authRepositoryProvider)),
);

final giftsProvider = StreamProvider(
  (ref) => ref.watch(giftRepositoryProvider).watchGifts(),
);
