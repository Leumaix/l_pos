import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/stock/presentation/restock_screen.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'restocking a cylinder through the actual UI adds to a nonzero starting '
    'count — same overwrite-bug regression already proven for gas, now for '
    'products',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(
            FakeInventoryRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // The default FakeInventoryRepository seeds the 3kg Cylinder at 12
      // — a nonzero starting count, deliberately, not a fresh/zero one.
      final inventory = container.read(inventoryRepositoryProvider);
      final products = inventory.currentProducts;
      final cylinder = products.firstWhere((p) => p.id == 'cyl-3kg');
      expect(cylinder.stockCount, 12, reason: 'sanity check on the fake seed');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RestockScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Cylinders'));
      await settle(tester);
      await tester.tap(find.text('3kg Cylinder'));
      await settle(tester);

      // Deliver 5 more.
      await tester.tap(find.text('5'));
      await settle(tester);

      expect(
        find.text('New stock: 17'),
        findsOneWidget,
      ); // 12 + 5, shown live before confirming

      await tester.tap(find.text('Add to stock'));
      await settle(tester);

      final updatedProducts = inventory.currentProducts;
      final updatedCylinder = updatedProducts.firstWhere(
        (p) => p.id == 'cyl-3kg',
      );

      // The whole point: old count (12) + this delivery (5), not just
      // the delivery on its own.
      expect(updatedCylinder.stockCount, 17);
      expect(updatedCylinder.stockCount, isNot(5));
    },
  );

  testWidgets(
    'a second product restock keeps adding on top, not replacing the running total',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(
            FakeInventoryRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final inventory = container.read(inventoryRepositoryProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RestockScreen()),
        ),
      );
      await settle(tester);

      Future<void> deliver(String digit) async {
        await tester.tap(find.text('Cylinders'));
        await settle(tester);
        await tester.tap(find.text('3kg Cylinder'));
        await settle(tester);
        await tester.tap(find.text(digit));
        await settle(tester);
        await tester.tap(find.text('Add to stock'));
        await settle(tester);
      }

      await deliver('3'); // +3 -> 12 + 3 = 15
      var products = inventory.currentProducts;
      expect(products.firstWhere((p) => p.id == 'cyl-3kg').stockCount, 15);

      await deliver('3'); // +3 again -> 15 + 3 = 18, not a reset to 3
      products = inventory.currentProducts;
      expect(products.firstWhere((p) => p.id == 'cyl-3kg').stockCount, 18);
    },
  );

  testWidgets(
    'restocking an out-of-stock accessory is reachable (unlike Sell, where it is blocked)',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(
            FakeInventoryRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final inventory = container.read(inventoryRepositoryProvider);

      // Drive an accessory to zero first.
      await inventory.decrementProductStock('acc-lighter', 50);
      final zeroed = inventory.currentProducts;
      expect(zeroed.firstWhere((p) => p.id == 'acc-lighter').stockCount, 0);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RestockScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Accessories'));
      await settle(tester);
      expect(find.text('Out of stock'), findsOneWidget);

      // Still tappable, unlike Sell's ProductTile.
      await tester.tap(find.text('Lighter'));
      await settle(tester);
      await tester.tap(find.text('2'));
      await settle(tester);
      await tester.tap(find.text('Add to stock'));
      await settle(tester);

      final restocked = inventory.currentProducts;
      expect(restocked.firstWhere((p) => p.id == 'acc-lighter').stockCount, 2);
    },
  );
}
