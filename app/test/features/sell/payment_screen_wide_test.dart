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

/// Wide-mode-only coverage — narrow mode (total, 2x2 method grid,
/// stacked sections) is unchanged from before Tier 2 and already covered
/// by payment_screen_test.dart.
void main() {
  testWidgets(
    'wide: the rail lists exactly the 4 supported methods, and selecting Cash shows the '
    'amount/keypad/Complete sale in the main pane, reachable and functional',
    (tester) async {
      // The real Itel tablet's landscape logical size.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.5;
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
            FakeCheckoutRepository(
              inventory: inventory,
              customers: customers,
              sales: sales,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(cartControllerProvider.notifier)
          .addCartProduct(_testProduct);
      await container.read(authStateProvider.future);

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

      // Exactly the 4 supported methods in the rail — no more, no fewer.
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);
      expect(find.text('Customer Account'), findsOneWidget);
      expect(find.text('Select a payment method'), findsOneWidget);
      // Nothing pulled in from the Odoo reference that this app doesn't
      // actually support.
      expect(find.textContaining('Invoice'), findsNothing);

      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();

      expect(find.text('Select a payment method'), findsNothing);
      expect(
        find.byType(GridView),
        findsNothing,
      ); // no narrow-mode method grid in wide mode

      for (final digit in ['1', '5', '0', '0', '0']) {
        await tester.tap(find.text(digit).first);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final completeSale = find.text('Complete sale');
      await tester.ensureVisible(completeSale);
      await tester.pumpAndSettle();

      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(
        tester.getRect(completeSale).bottom,
        lessThanOrEqualTo(screenHeight),
      );

      await tester.tap(completeSale);
      await tester.pumpAndSettle();

      expect(completedSale, isNotNull);
      expect(completedSale!.total, 15000);
    },
  );
}
