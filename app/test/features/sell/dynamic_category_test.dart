import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/presentation/sell_screen.dart';
import 'package:leumadepos/features/stock/presentation/restock_screen.dart';
import 'package:leumadepos/features/stock/presentation/stock_screen.dart';

/// Proves the core architectural claim behind the owner-managed catalog:
/// Sell, Stock, and Restock render whatever categories/products exist in
/// the repository — a category and product created here (the same way
/// Manage Catalog would create them, via the repository directly) shows
/// up on all three screens with ZERO code changes to those screens.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> containerWithNewCategory() async {
    final inventory = FakeInventoryRepository();
    final category = await inventory.createCategory('Spare Parts');
    await inventory.createProduct(
      categoryId: category.id,
      name: 'Valve',
      price: 500,
      stockCount: 10,
    );
    return ProviderContainer(
      overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
    );
  }

  testWidgets('a newly-created category and product show up on Sell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await containerWithNewCategory();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: SellScreen(onGoToPayment: () {})),
      ),
    );
    await settle(tester);

    expect(find.text('Spare Parts'), findsOneWidget); // the new category chip
    expect(
      find.text('Valve'),
      findsNothing,
    ); // not shown until that tab is selected

    await tester.ensureVisible(find.text('Spare Parts'));
    await settle(tester);
    await tester.tap(find.text('Spare Parts'));
    await settle(tester);

    expect(find.text('Valve'), findsOneWidget);
  });

  testWidgets('a newly-created category and product show up on Stock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await containerWithNewCategory();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: StockScreen(onRestock: () {})),
      ),
    );
    await settle(tester);

    expect(find.text('Spare Parts'), findsOneWidget);

    await tester.ensureVisible(find.text('Spare Parts'));
    await settle(tester);
    await tester.tap(find.text('Spare Parts'));
    await settle(tester);

    expect(find.text('Valve'), findsOneWidget);
    expect(find.text('10'), findsOneWidget); // its stock count in the table
  });

  testWidgets('a newly-created category and product show up on Restock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = await containerWithNewCategory();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RestockScreen()),
      ),
    );
    await settle(tester);

    expect(find.text('Spare Parts'), findsOneWidget);

    await tester.ensureVisible(find.text('Spare Parts'));
    await settle(tester);
    await tester.tap(find.text('Spare Parts'));
    await settle(tester);

    expect(find.text('Valve'), findsOneWidget);
    expect(find.text('10 in stock'), findsOneWidget);
  });
}
