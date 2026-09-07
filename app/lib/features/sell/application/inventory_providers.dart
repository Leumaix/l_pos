import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../../core/business_config.dart';
import '../../auth/application/auth_providers.dart';
import '../data/firebase_inventory_repository.dart';
import '../data/inventory_repository.dart';

/// Same "one-line swap" pattern as auth/invites/business settings: real
/// by default (gas stays in-memory/hardcoded within it — see
/// FirebaseInventoryRepository's doc comment), overridden with
/// FakeInventoryRepository in tests.
final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => FirebaseInventoryRepository(ref.watch(authRepositoryProvider)),
);

final gasStockProvider = StreamProvider((ref) => ref.watch(inventoryRepositoryProvider).watchGasStock());

final _gasRateStreamProvider = StreamProvider((ref) => ref.watch(inventoryRepositoryProvider).watchGasRate());

/// Same "plain value, not async" contract every existing call site relies
/// on — now backed by a live Firestore stream instead of a hardcoded
/// constant, with [kDefaultGasRateNairaPerKg] covering the brief
/// initial-load window and any read error.
final gasRateProvider = Provider<GasRate>((ref) {
  return ref.watch(_gasRateStreamProvider).valueOrNull ?? const GasRate(kDefaultGasRateNairaPerKg);
});

final productsProvider = StreamProvider((ref) => ref.watch(inventoryRepositoryProvider).watchProducts());

final categoriesProvider = StreamProvider((ref) => ref.watch(inventoryRepositoryProvider).watchCategories());
