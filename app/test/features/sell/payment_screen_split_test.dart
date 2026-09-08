import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/auth_repository.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/sell/application/cart_controller.dart';
import 'package:leumadepos/features/sell/application/checkout_providers.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/application/sales_providers.dart';
import 'package:leumadepos/features/sell/data/checkout_repository.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/data/sales_repository.dart';
import 'package:leumadepos/features/sell/domain/product.dart';
import 'package:leumadepos/features/sell/domain/sale.dart';
import 'package:leumadepos/features/sell/presentation/payment_screen.dart';

const _testProduct = Product(
  id: 'cyl-6kg',
  categoryId: 'cat-cylinders',
  name: '6kg Cylinder',
  price: 15000,
  stockCount: 9,
);

const _testStaff = AppUser(
  uid: 'staff-1',
  name: 'Ifeoma',
  email: 'ifeoma@leumadepos.test',
  role: 'attendant',
);

/// Split-entry coverage — a deliberate, reachable-but-not-in-the-way path
/// on top of payment_screen_test.dart's single-method (fast path) and
/// payment_screen_wide_test.dart's wide-mode coverage, both of which stay
/// unchanged by this feature (same widget tree, same taps, still pass).
void main() {
  // The split flow stacks more content above the keypad than a plain
  // single-method sale ever does (the committed-lines summary, the "Add
  // another payment method" button), so — unlike the existing
  // single-method tests — digit keys can genuinely scroll off a phone-
  // sized viewport mid-flow. ensureVisible before every tap, not just
  // before "Complete sale".
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> typeAmount(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tapVisible(tester, find.text(digit).first);
    }
    await tester.pumpAndSettle();
  }


  Future<ProviderContainer> setUpCart({
    required FakeInventoryRepository inventory,
    required FakeCustomerRepository customers,
    required FakeSalesRepository sales,
  }) async {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(_testStaff)),
        inventoryRepositoryProvider.overrideWithValue(inventory),
        customerRepositoryProvider.overrideWithValue(customers),
        salesRepositoryProvider.overrideWithValue(sales),
        checkoutRepositoryProvider.overrideWithValue(
          FakeCheckoutRepository(inventory: inventory, customers: customers, sales: sales),
        ),
      ],
    );
    container.read(cartControllerProvider.notifier).addCartProduct(_testProduct); // total 15000
    await container.read(authStateProvider.future);
    return container;
  }

  testWidgets(
    'splitting part card + part cash produces a Sale.payments list buildSale/rules would accept — '
    'sums to the total, only cash negative (none here, exact split, no change)',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final inventory = FakeInventoryRepository();
      final customers = FakeCustomerRepository();
      final sales = FakeSalesRepository();
      final container = await setUpCart(inventory: inventory, customers: customers, sales: sales);
      addTearDown(container.dispose);

      Sale? completedSale;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PaymentScreen(
              onSaleComplete: (sale) => completedSale = sale,
              onEmptyCart: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fast path untouched: Card alone would auto-charge the full
      // 15000 with no keypad at all — the "Confirm to charge" card.
      await tapVisible(tester, find.text('Card'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Confirm to charge'), findsOneWidget);
      // "Complete sale" would already be enabled here for the fast
      // path — Complete sale button check omitted, this test is about
      // the split path specifically.

      // Deliberately reach for a split.
      await tapVisible(tester, find.text('Split — pay only part with this method'));
      await tester.pumpAndSettle();

      // The keypad is now showing for Card — type a PARTIAL amount.
      await typeAmount(tester, '10000');

      expect(find.textContaining('Still need'), findsOneWidget);
      expect(find.text('Add another payment method'), findsOneWidget);

      await tapVisible(tester, find.text('Add another payment method'));
      await tester.pumpAndSettle();

      // The committed line shows in the running summary.
      expect(find.text('Already added'), findsOneWidget);
      expect(find.text('Card'), findsWidgets); // method tile label + summary row
      expect(find.text('Remaining'), findsOneWidget);

      // Second method — Cash always shows its keypad directly, no
      // reveal tap needed, matching the fast path's own cash behavior.
      await tapVisible(tester, find.text('Cash'));
      await tester.pumpAndSettle();

      await typeAmount(tester, '5000');

      expect(find.text('Balances exactly'), findsOneWidget);
      // Nothing left to split further.
      expect(find.text('Add another payment method'), findsNothing);

      await tapVisible(tester, find.text('Complete sale'));
      await tester.pumpAndSettle();

      expect(completedSale, isNotNull);
      expect(completedSale!.total, 15000);
      expect(completedSale!.payments, hasLength(2));
      final byMethod = {for (final p in completedSale!.payments) p.method: p.amountNaira};
      expect(byMethod[PaymentMethod.card], 10000);
      expect(byMethod[PaymentMethod.cash], 5000);
      expect(completedSale!.payments.fold(0, (sum, p) => sum + p.amountNaira), 15000);
      expect(completedSale!.changeGivenNaira, 0);
    },
  );

  testWidgets(
    'overpaying the final split line produces a separate negative cash change line, not a negative '
    'line on the overpaid method',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final inventory = FakeInventoryRepository();
      final customers = FakeCustomerRepository();
      final sales = FakeSalesRepository();
      final container = await setUpCart(inventory: inventory, customers: customers, sales: sales);
      addTearDown(container.dispose);

      Sale? completedSale;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PaymentScreen(
              onSaleComplete: (sale) => completedSale = sale,
              onEmptyCart: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Transfer'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Split — pay only part with this method'));
      await tester.pumpAndSettle();

      // Commit a small transfer line first (10000 of 15000).
      await typeAmount(tester, '10000');
      await tapVisible(tester, find.text('Add another payment method'));
      await tester.pumpAndSettle();

      // Second line, cash, OVERPAID: 8000 against a 5000 remainder.
      await tapVisible(tester, find.text('Cash'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '8000');

      expect(find.text('Change: ₦3,000'), findsOneWidget);

      await tapVisible(tester, find.text('Complete sale'));
      await tester.pumpAndSettle();

      expect(completedSale, isNotNull);
      expect(completedSale!.total, 15000);
      // 3 lines: transfer 10000, cash 8000 (the real tendered amount,
      // never capped), and a separate negative cash change line.
      expect(completedSale!.payments, hasLength(3));
      final transferLine = completedSale!.payments.firstWhere((p) => p.method == PaymentMethod.transfer);
      expect(transferLine.amountNaira, 10000);
      final cashLines = completedSale!.payments.where((p) => p.method == PaymentMethod.cash).toList();
      expect(cashLines, hasLength(2));
      expect(cashLines.map((p) => p.amountNaira), containsAll([8000, -3000]));
      expect(completedSale!.cashReceivedNaira, 8000);
      expect(completedSale!.changeGivenNaira, 3000);
      expect(completedSale!.payments.fold(0, (sum, p) => sum + p.amountNaira), 15000);
    },
  );
}
