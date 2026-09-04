import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gas_stock/gas_stock.dart';

import '../../auth/application/auth_providers.dart';
import '../../sell/application/inventory_providers.dart';

/// Commits a gas delivery. Reads the current on-hand stock synchronously
/// (InventoryRepository.currentGasStock), runs it through gas_stock's pure
/// restock() to get the exact units to add, then commits that delta via
/// addGasStock — which only ever adds on top of existing stock, never
/// replaces it. See gas_stock's restock() docs and
/// InventoryRepository.addGasStock for why that matters: a delivery must
/// never lose leftover gas from before it arrived.
class RestockController {
  final Ref ref;

  RestockController(this.ref);

  Future<GasRestockResult> commitRestock(num kgDelivered) async {
    final inventory = ref.read(inventoryRepositoryProvider);
    final staff = ref.read(authStateProvider).valueOrNull;
    if (staff == null) {
      throw StateError('commitRestock called with no signed-in staff member');
    }
    final result = restock(inventory.currentGasStock, kgDelivered, inventory.gasRate);
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
