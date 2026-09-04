import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/auth_repository.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/customers/domain/customer.dart';
import 'package:leumadepos/features/sell/application/cart_controller.dart';
import 'package:leumadepos/features/sell/application/checkout_controller.dart';
import 'package:leumadepos/features/sell/application/checkout_providers.dart';
import 'package:leumadepos/features/sell/data/checkout_repository.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/data/sales_repository.dart';
import 'package:leumadepos/features/sell/domain/product.dart';
import 'package:leumadepos/features/sell/domain/sale.dart';

const _testStaff = AppUser(
  uid: 'staff-1',
  name: 'Ifeoma',
  email: 'ifeoma@leumadepos.test',
  role: 'attendant',
);

const _testProduct = Product(
  id: 'cyl-6kg',
  categoryId: 'cat-cylinders',
  name: '6kg Cylinder',
  price: 15000,
  stockCount: 9,
);

void main() {
  late FakeInventoryRepository inventory;
  late FakeCustomerRepository customers;
  late FakeSalesRepository sales;
  late ProviderContainer container;

  setUp(() async {
    inventory = FakeInventoryRepository();
    customers = FakeCustomerRepository();
    sales = FakeSalesRepository();
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(_testStaff)),
        checkoutRepositoryProvider.overrideWithValue(
          FakeCheckoutRepository(inventory: inventory, customers: customers, sales: sales),
        ),
      ],
    );
    // authStateProvider is a StreamProvider; Stream.value's first event
    // still arrives on a later microtask, not synchronously. Warm it up
    // so it's already AsyncData by the time completeSale reads it below
    // — otherwise it's mistaken for "no signed-in staff" (same fix as
    // payment_screen_test.dart).
    await container.read(authStateProvider.future);
  });

  tearDown(() => container.dispose());

  test('a gas-only cash sale deducts gas stock and records the sale, no product/customer changes', () async {
    final startingGas = inventory.currentGasStock.units;
    container.read(cartControllerProvider.notifier).addGasKg(
      kg: 2,
      currentGasStock: inventory.currentGasStock,
      rate: inventory.gasRate,
    );
    final expectedTotal = container.read(cartControllerProvider).total;

    final sale = await container
        .read(checkoutControllerProvider)
        .completeSale(method: PaymentMethod.cash, cashGiven: expectedTotal);

    expect(inventory.currentGasStock.units, startingGas - sale.total);
    final recorded = await sales.watchSales().first;
    expect(recorded.map((s) => s.id), contains(sale.id));
  });

  test('a product-only cash sale decrements product stock and records the sale', () async {
    container.read(cartControllerProvider.notifier).addCartProduct(_testProduct);

    final sale = await container
        .read(checkoutControllerProvider)
        .completeSale(method: PaymentMethod.cash, cashGiven: 15000);

    expect(inventory.currentProducts.firstWhere((p) => p.id == _testProduct.id).stockCount, 8);
    final recorded = await sales.watchSales().first;
    expect(recorded.map((s) => s.id), contains(sale.id));
  });

  test('a mixed cart (gas + product) commits both deductions in one sale', () async {
    container.read(cartControllerProvider.notifier).addGasKg(
      kg: 1,
      currentGasStock: inventory.currentGasStock,
      rate: inventory.gasRate,
    );
    container.read(cartControllerProvider.notifier).addCartProduct(_testProduct);
    final startingGas = inventory.currentGasStock.units;
    final expectedTotal = container.read(cartControllerProvider).total;

    final sale = await container
        .read(checkoutControllerProvider)
        .completeSale(method: PaymentMethod.cash, cashGiven: expectedTotal);

    expect(inventory.currentProducts.firstWhere((p) => p.id == _testProduct.id).stockCount, 8);
    expect(inventory.currentGasStock.units, lessThan(startingGas));
    expect(sale.items, hasLength(2));
  });

  test('a customer-account sale records a credit sale against the chosen customer', () async {
    container.read(cartControllerProvider.notifier).addCartProduct(_testProduct);
    const customer = Customer(id: 'cust-1', name: 'Ngozi Eze', phone: '08051112222', balance: 5000);

    final sale = await container
        .read(checkoutControllerProvider)
        .completeSale(method: PaymentMethod.customerAccount, customer: customer);

    final allCustomers = await customers.watchCustomers().first;
    expect(allCustomers.firstWhere((c) => c.id == 'cust-1').balance, 5000 + sale.total);
  });

  test('newSaleId is called before buildSale — the returned Sale.id matches what was committed', () async {
    container.read(cartControllerProvider.notifier).addCartProduct(_testProduct);

    final sale = await container
        .read(checkoutControllerProvider)
        .completeSale(method: PaymentMethod.cash, cashGiven: 15000);

    final recorded = await sales.watchSales().first;
    expect(recorded.single.id, sale.id);
  });
}
