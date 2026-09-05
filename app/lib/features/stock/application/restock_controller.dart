import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../auth/application/auth_providers.dart';
import '../../sell/application/inventory_providers.dart';

/// Commits a gas delivery. Reads the current rate + on-hand stock via
/// InventoryRepository.fetchCurrentRateAndStock() — a fresh, one-shot
/// authoritative read, NOT the currentGasStock/gasRate cached getters —
/// runs it through gas_stock's pure restock() to get the exact units to
/// add, then commits that delta via addGasStock — which only ever adds
/// on top of existing stock, never replaces it. See gas_stock's
/// restock() docs and InventoryRepository.addGasStock for why that
/// matters: a delivery must never lose leftover gas from before it
/// arrived.
///
/// Why not the cached getters: unlike checkout (whose actual write is a
/// relative FieldValue.increment that never depends on the cached read
/// being correct), restock's unitsAdded is computed directly from
/// kgDelivered * rate — a wrong cached rate produces a genuinely wrong,
/// permanently-written delta, not just a stale display. And since this
/// is the ONLY call site in the app that ever touches gasRate/
/// currentGasStock at all, their lazy subscriptions are GUARANTEED to
/// still be at their cold-start defaults on literally the first restock
/// of every session — not a narrow race, a deterministic miss.
class RestockController {
  final Ref ref;

  RestockController(this.ref);

  Future<GasRestockResult> commitRestock(num kgDelivered) async {
    final inventory = ref.read(inventoryRepositoryProvider);
    final staff = ref.read(authStateProvider).valueOrNull;
    if (staff == null) {
      throw StateError('commitRestock called with no signed-in staff member');
    }
    final (rate, stock) = await inventory.fetchCurrentRateAndStock();
    final result = restock(stock, kgDelivered, rate);
    await inventory.addGasStock(result.unitsAdded, staffId: staff.uid, staffName: staff.name);
    return result;
  }

  /// A cylinder/accessory delivery — same additive-never-overwrite
  /// contract as [commitRestock]: [quantityAdded] is added on top of
  /// whatever stock that product already has, never replaces it.
  Future<void> commitProductRestock(String productId, int quantityAdded) async {
    if (quantityAdded <= 0) {
      throw ArgumentError.value(quantityAdded, 'quantityAdded', 'must be positive');
    }
    final inventory = ref.read(inventoryRepositoryProvider);
    await inventory.incrementProductStock(productId, quantityAdded);
  }
}

final restockControllerProvider = Provider((ref) => RestockController(ref));
