import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/presentation/gas_numpad_sheet.dart';

/// Regression coverage for a real bug found testing on a physical tablet
/// in landscape: at a short viewport height, this sheet's content (title,
/// mode toggle, big numeric display, 4-row keypad, Add to cart button)
/// overflowed its non-scrolling Column by 286px — the keypad's lower rows
/// and the Add to cart button were rendered off-screen and unreachable by
/// touch. Fixed by wrapping the Column in a SingleChildScrollView; this
/// test pins that fix by rendering at a landscape-tablet-style height and
/// asserting the button is both present and actually tappable, with no
/// overflow error reported.
void main() {
  testWidgets(
    'the gas numpad sheet stays usable at a short, landscape-style '
    'viewport height — the numeric keypad and Add to cart button must '
    'never be pushed off-screen and unreachable',
    (tester) async {
      // The real Itel tablet this bug was found on: 800x1280 physical
      // pixels at 240dpi (1.5x), landscape. devicePixelRatio matters here
      // as much as physicalSize — at the wrong (e.g. 1.0) ratio, the
      // simulated logical height is far taller than the real device's
      // ~533dp and the overflow doesn't reproduce at all, silently
      // defeating this test. 1.5x is what makes this test real.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showGasNumpadSheet(context),
                  child: const Text('open sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      // No layout/render error just from opening the sheet at this height.
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();

      // The primary regression guard: a genuine RenderFlex overflow
      // throws a FlutterError that takeException() catches — proven by
      // reverting the SingleChildScrollView fix locally and confirming
      // this exact line fails with "A RenderFlex overflowed by N
      // pixels". Starting below the fold at this point is fine and
      // expected (that's what scrolling is for) — the bug was content
      // that could never be reached at all, scrolling included.
      expect(tester.takeException(), isNull);

      final addToCart = find.text('Add to cart');
      expect(addToCart, findsOneWidget);

      // Confirms scrolling actually works, not just that nothing
      // crashed: ensureVisible only moves a widget inside a real
      // Scrollable — with no scrollable ancestor (the broken shape) it
      // silently no-ops, leaving the button whichever side of the
      // screen it started on. A widget-tree hit (as tester.tap alone
      // would check) isn't enough either — it taps a widget's computed
      // center regardless of whether that coordinate is within the
      // physical screen, which is exactly how the real 286px-off-screen
      // button slipped through until it was hit on a real device.
      await tester.ensureVisible(addToCart);
      await tester.pumpAndSettle();

      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final buttonRect = tester.getRect(addToCart);
      expect(
        buttonRect.bottom,
        lessThanOrEqualTo(screenHeight),
        reason:
            'Add to cart sits at y=${buttonRect.bottom} even after '
            'ensureVisible, past the bottom of a ${screenHeight}px-tall '
            'viewport — unreachable by a real touch.',
      );

      await tester.tap(addToCart);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // A successful tap adds to cart and pops the sheet.
      expect(find.text('open sheet'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets(
    'wide: at the real Itel tablet landscape size, the display and Add to '
    'cart button stay in the same pane, strictly left of the keypad, and '
    'the full add-to-cart flow still works',
    (tester) async {
      // Same real dimensions used throughout the Tier 1/2 landscape
      // regression tests — see login_screen_wide_test.dart /
      // payment_screen_wide_test.dart / keypad_entry_layout_test.dart.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository())],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showGasNumpadSheet(context),
                  child: const Text('open sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      final title = find.text('Cooking Gas');
      final addToCart = find.text('Add to cart');
      final keypadDigit = find.text('1');
      expect(title, findsOneWidget);
      expect(addToCart, findsOneWidget);
      expect(keypadDigit, findsOneWidget);

      // The defining property of the wide split: the display and the
      // action button both sit in the same (left) pane, strictly left
      // of the keypad's pane — not below it.
      final titleX = tester.getTopLeft(title).dx;
      final addToCartX = tester.getTopLeft(addToCart).dx;
      final keypadX = tester.getTopLeft(keypadDigit).dx;
      expect(titleX, lessThan(keypadX));
      expect(addToCartX, lessThan(keypadX));

      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(tester.getRect(addToCart).bottom, lessThanOrEqualTo(screenHeight));

      await tester.tap(keypadDigit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('open sheet'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );
}
