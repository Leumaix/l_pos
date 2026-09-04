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

void main() {
  testWidgets(
    'completing a cash sale calls onSaleComplete, never onEmptyCart — '
    'regression for a race where clearing the cart mid-checkout could '
    'trigger the "nothing to pay for" bounce-back before navigation ran',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final inventory = FakeInventoryRepository();
      final customers = FakeCustomerRepository();
      final sales = FakeSalesRepository();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_testStaff)),
          inventoryRepositoryProvider.overrideWithValue(inventory),
          customerRepositoryProvider.overrideWithValue(customers),
          salesRepositoryProvider.overrideWithValue(sales),
          // CheckoutController no longer reads the three providers above
          // directly for the commit itself — only checkoutRepositoryProvider
          // matters for that; wired to the same fake instances so any
          // direct UI reads (e.g. the customer-account section) stay
          // consistent with what a completed sale actually commits.
          checkoutRepositoryProvider.overrideWithValue(
            FakeCheckoutRepository(inventory: inventory, customers: customers, sales: sales),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(cartControllerProvider.notifier)
          .addCartProduct(_testProduct); // total 15000
      // authStateProvider is a StreamProvider; reading it lazily starts
      // loading, but Stream.value's first event still arrives on a later
      // microtask. Warm it up so it's already AsyncData by the time
      // completeSale reads it below — otherwise it's mistaken for "no
      // signed-in staff".
      await container.read(authStateProvider.future);

      Sale? completedSale;
      var emptyCartCalled = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PaymentScreen(
              onSaleComplete: (sale) => completedSale = sale,
              onEmptyCart: () => emptyCartCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();

      for (final digit in ['1', '5', '0', '0', '0']) {
        await tester.tap(find.text(digit).first);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Complete sale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();

      expect(completedSale, isNotNull);
      expect(completedSale!.total, 15000);
      expect(emptyCartCalled, isFalse);
    },
  );

  testWidgets(
    'creating a new customer inline from Customer Account auto-selects them into the sale, '
    'with no opening-balance field — this path is a walk-in with no history, always zero',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final inventory = FakeInventoryRepository();
      final customers = FakeCustomerRepository();
      final sales = FakeSalesRepository();
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
      addTearDown(container.dispose);
      container.read(cartControllerProvider.notifier).addCartProduct(_testProduct);
      await container.read(authStateProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PaymentScreen(onSaleComplete: (_) {}, onEmptyCart: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Customer Account'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New customer'));
      await tester.pumpAndSettle();

      // No opening-balance field on this path, regardless of role.
      expect(find.text('Opening balance (₦) — optional'), findsNothing);

      final sheetFields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
      await tester.enterText(sheetFields.at(0), 'Mid-Sale Walk-in');
      await tester.enterText(sheetFields.at(1), '08099998888');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Auto-selected: Payment now shows the "selected customer" view
      // (name + Change button), not the search/list view — no separate
      // trip back to search for the customer just created.
      expect(find.text('Mid-Sale Walk-in'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Current balance'), findsOneWidget);
    },
  );
}
