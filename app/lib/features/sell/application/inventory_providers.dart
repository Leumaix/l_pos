import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/firebase_inventory_repository.dart';
import '../data/inventory_repository.dart';

/// Same "one-line swap" pattern as auth/invites/business settings: real
/// by default (gas stays in-memory/hardcoded within it — see
/// FirebaseInventoryRepository's doc comment), overridden with
/// FakeInventoryRepository in tests.
final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => FirebaseInventoryRepository(ref.watch(firebaseAuthRepositoryProvider)),
);

final gasStockProvider = StreamProvider((ref) => ref.watch(inventoryRepositoryProvider).watchGasStock());

final gasRateProvider = Provider((ref) => ref.watch(inventoryRepositoryProvider).gasRate);

final productsProvider = StreamProvider((ref) => ref.watch(inventoryRepositoryProvider).watchProducts());

final categoriesProvider = StreamProvider((ref) => ref.watch(inventoryRepositoryProvider).watchCategories());
