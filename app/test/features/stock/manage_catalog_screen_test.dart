import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/stock/presentation/manage_catalog_screen.dart';
import 'package:leumadepos/features/stock/presentation/manage_category_products_screen.dart';

/// The security half (only an active owner can create/update/delete a
/// category or product; staff can move stockCount only) is covered
/// against a real Firestore emulator in
/// firestore_rules_tests/catalog_rules.test.mjs. This file covers the
/// other half: the Manage Catalog screens' own UI/state logic against a
/// fake repository.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> useDefaultPhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'a category row makes it visually obvious it opens to add/edit products — '
    'a real owner reported not realizing a new category could be tapped at all',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      final inventory = FakeInventoryRepository();
      final container = ProviderContainer(
        overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ManageCatalogScreen()),
        ),
      );
      await settle(tester);

      expect(find.text('0 products — tap to add or edit'), findsNothing); // Cylinders is seeded non-empty
      expect(find.textContaining('— tap to add or edit'), findsWidgets);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    },
  );

  testWidgets('adding a category adds it to the list', (tester) async {
    await useDefaultPhoneSurface(tester);
    final inventory = FakeInventoryRepository();
    final container = ProviderContainer(
      overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ManageCatalogScreen()),
      ),
    );
    await settle(tester);

    expect(find.text('Cylinders'), findsOneWidget); // seeded default
    expect(find.text('Spare Parts'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Spare Parts');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(find.text('Spare Parts'), findsOneWidget);
    expect(inventory.currentCategories.any((c) => c.name == 'Spare Parts'), isTrue);
  });

  testWidgets('renaming a category updates it in place', (tester) async {
    await useDefaultPhoneSurface(tester);
    final inventory = FakeInventoryRepository();
    final container = ProviderContainer(
      overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ManageCatalogScreen()),
      ),
    );
    await settle(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await settle(tester);

    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, 'Gas Cylinders');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('Gas Cylinders'), findsOneWidget);
    expect(find.text('Cylinders'), findsNothing);
  });

  testWidgets('deleting an empty category removes it', (tester) async {
    await useDefaultPhoneSurface(tester);
    final inventory = FakeInventoryRepository();
    // Clear the seeded products so Accessories is genuinely empty.
    for (final product in inventory.currentProducts.where((p) => p.categoryId == 'cat-accessories').toList()) {
      await inventory.deleteProduct(product.id);
    }
    final container = ProviderContainer(
      overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ManageCatalogScreen()),
      ),
    );
    await settle(tester);

    expect(find.text('Accessories'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).last); // Accessories row (seeded after Cylinders)
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(find.text('Accessories'), findsNothing);
    expect(inventory.currentCategories.any((c) => c.name == 'Accessories'), isFalse);
  });

  testWidgets('deleting a category that still has products is blocked with a clear message', (
    tester,
  ) async {
    await useDefaultPhoneSurface(tester);
    final inventory = FakeInventoryRepository(); // Cylinders has 4 seeded products
    final container = ProviderContainer(
      overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ManageCatalogScreen()),
      ),
    );
    await settle(tester);

    await tester.tap(find.byIcon(Icons.delete_outline).first); // Cylinders row
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(find.text('Move or delete the 4 products in "Cylinders" first.'), findsOneWidget);
    // Never actually deleted — never orphans its products.
    expect(inventory.currentCategories.any((c) => c.name == 'Cylinders'), isTrue);
    expect(inventory.currentProducts.any((p) => p.categoryId == 'cat-cylinders'), isTrue);
  });

  testWidgets('adding a product inside a category shows up in that category\'s product list', (
    tester,
  ) async {
    await useDefaultPhoneSurface(tester);
    final inventory = FakeInventoryRepository();
    final container = ProviderContainer(
      overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ManageCategoryProductsScreen(categoryId: 'cat-cylinders', categoryName: 'Cylinders'),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('Add product'));
    await settle(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '20kg Cylinder'); // name
    await tester.enterText(fields.at(1), '45000'); // price
    await tester.enterText(fields.at(2), '3'); // starting stock
    await tester.pump(const Duration(milliseconds: 10));

    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('20kg Cylinder'), findsOneWidget);
    final created = inventory.currentProducts.firstWhere((p) => p.name == '20kg Cylinder');
    expect(created.price, 45000);
    expect(created.stockCount, 3);
    expect(created.categoryId, 'cat-cylinders');
  });

  testWidgets('editing a product changes name/price but never its stock count', (tester) async {
    await useDefaultPhoneSurface(tester);
    final inventory = FakeInventoryRepository();
    final container = ProviderContainer(
      overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
    );
    addTearDown(container.dispose);

    final originalStock = inventory.currentProducts.firstWhere((p) => p.id == 'cyl-3kg').stockCount;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ManageCategoryProductsScreen(categoryId: 'cat-cylinders', categoryName: 'Cylinders'),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined).first); // 3kg Cylinder
    await settle(tester);

    // No stock field at all on the edit form.
    expect(find.text('Starting stock count'), findsNothing);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '8500'); // price
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.text('Save'));
    await settle(tester);

    final updated = inventory.currentProducts.firstWhere((p) => p.id == 'cyl-3kg');
    expect(updated.price, 8500);
    expect(updated.stockCount, originalStock); // untouched by the edit
  });

  testWidgets('deleting a product removes it from the list', (tester) async {
    await useDefaultPhoneSurface(tester);
    final inventory = FakeInventoryRepository();
    final container = ProviderContainer(
      overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ManageCategoryProductsScreen(categoryId: 'cat-cylinders', categoryName: 'Cylinders'),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('3kg Cylinder'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(find.text('3kg Cylinder'), findsNothing);
    expect(inventory.currentProducts.any((p) => p.id == 'cyl-3kg'), isFalse);
  });
}
