import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/domain/product.dart';
import 'package:leumadepos/features/stock/presentation/product_restock_sheet.dart';

/// Same landscape-tablet regression shape as
/// test/features/sell/gas_numpad_sheet_test.dart — this sheet shares the
/// exact same display/keypad/button structure (now via KeypadEntryLayout)
/// and had the identical Tier 1 overflow bug before being redesigned.
void main() {
  const product = Product(
    id: 'cyl-3kg',
    categoryId: 'cat-cylinders',
    name: '3kg Cylinder',
    price: 8000,
    stockCount: 12,
  );

  testWidgets(
    'the restock sheet stays usable at a short, landscape-style viewport '
    'height — the numeric keypad and Add to stock button must never be '
    'pushed off-screen and unreachable',
    (tester) async {
      // The real Itel tablet: 800x1280 physical @ 240dpi (1.5x), landscape.
      // See gas_numpad_sheet_test.dart for why the ratio matters as much
      // as the size — the wrong ratio silently defeats this test.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.5;
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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showProductRestockSheet(context, product),
                  child: const Text('open sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final addToStock = find.text('Add to stock');
      expect(addToStock, findsOneWidget);

      await tester.ensureVisible(addToStock);
      await tester.pumpAndSettle();

      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final buttonRect = tester.getRect(addToStock);
      expect(
        buttonRect.bottom,
        lessThanOrEqualTo(screenHeight),
        reason:
            'Add to stock sits at y=${buttonRect.bottom} even after '
            'ensureVisible, past the bottom of a ${screenHeight}px-tall '
            'viewport — unreachable by a real touch.',
      );

      await tester.tap(addToStock);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('open sheet'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );
}
