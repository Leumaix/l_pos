import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/presentation/sell_screen.dart';

/// Wide-mode-only coverage — narrow mode (tabs above a scrolling grid,
/// floating cart bar + showCartSheet) is unchanged from before Tier 2 and
/// already covered by other Sell-related tests.
void main() {
  Future<void> useTabletSurface(WidgetTester tester) async {
    // The real Itel tablet's landscape logical size — same dimensions
    // used throughout the Tier 1/2 landscape regression tests.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('wide: the rail holds only the running cart/total/Go to payment — category tabs sit in the '
      'main pane above the product grid, not in the rail — and adding a product updates the cart '
      'without opening a bottom sheet', (tester) async {
    await useTabletSurface(tester);

    var goToPaymentCalled = false;
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
          home: SellScreen(onGoToPayment: () => goToPaymentCalled = true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Rail and product grid render side by side — no floating cart bar
    // in wide mode.
    expect(find.text('Cart'), findsOneWidget);
    expect(find.text('Cart is empty'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_cart), findsNothing);

    // Category tabs live in the main pane (right of the rail's "Cart"
    // heading), not stacked inside the rail itself.
    final cartHeadingX = tester.getTopLeft(find.text('Cart')).dx;
    final cylindersTabX = tester.getTopLeft(find.text('Cylinders')).dx;
    expect(cylindersTabX, greaterThan(cartHeadingX));

    await tester.tap(find.text('Cylinders'));
    await tester.pumpAndSettle();

    expect(find.text('3kg Cylinder'), findsOneWidget);

    await tester.tap(find.text('3kg Cylinder').first);
    await tester.pumpAndSettle();

    // The rail — not a bottom sheet — now shows the line and total:
    // "3kg Cylinder" now appears twice (the grid tile + the new cart
    // line), and "Total" (unique to the rail) is present.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Cart is empty'), findsNothing);
    expect(find.text('3kg Cylinder'), findsNWidgets(2));
    expect(find.text('Total'), findsOneWidget);

    await tester.tap(find.text('Go to payment'));
    await tester.pumpAndSettle();

    expect(goToPaymentCalled, isTrue);
  });
}
