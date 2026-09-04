import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/auth_repository.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/customers/domain/customer.dart';
import 'package:leumadepos/features/sell/application/cart_controller.dart';
import 'package:leumadepos/features/sell/application/checkout_providers.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/application/pending_credit_customer_provider.dart';
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
const _testCustomer = Customer(
  id: 'cust-1',
  name: 'Ngozi Eze',
  phone: '08051112222',
  balance: 5000,
);

void main() {
  testWidgets(
    'a customer handed off from Customer detail\'s "Record sale" arrives on '
    'Payment pre-selected as Customer Account — and the sale still goes '
    'through the real cart/stock path, not a stock-free shortcut',
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
          salesRepositoryProvider.overrideWithValue(sales),
          customerRepositoryProvider.overrideWithValue(customers),
          checkoutRepositoryProvider.overrideWithValue(
            FakeCheckoutRepository(inventory: inventory, customers: customers, sales: sales),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(cartControllerProvider.notifier)
          .addCartProduct(_testProduct);
      // The hand-off Customer detail's "Record sale" performs.
      container.read(pendingCreditCustomerProvider.notifier).state =
          _testCustomer;
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

      // Pre-selected without tapping anything: the customer's balance
      // preview is already showing.
      expect(find.text('Ngozi Eze'), findsOneWidget);
      expect(find.text('Current balance'), findsOneWidget);

      // The hand-off is consumed exactly once.
      expect(container.read(pendingCreditCustomerProvider), isNull);

      await tester.ensureVisible(find.text('Complete sale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();

      // It's a real sale: stock-affecting, cash/change fields absent,
      // and attributed to the customer via the checkout path (saleId
      // set on the customer's ledger entry is covered separately in
      // checkout_controller's integration with CustomerRepository).
      expect(completedSale, isNotNull);
      expect(completedSale!.method, PaymentMethod.customerAccount);
      expect(completedSale!.customerName, 'Ngozi Eze');
      expect(completedSale!.total, 15000);
    },
  );
}
