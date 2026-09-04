import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/customers/domain/customer_transaction.dart';

void main() {
  late FakeCustomerRepository repo;

  setUp(() {
    repo = FakeCustomerRepository();
  });

  Future<T> firstValue<T>(Stream<T> stream) => stream.first;

  test('a repayment larger than the balance goes negative — store credit, not clamped at zero', () async {
    // cust-1 seeds at 5000.
    await repo.recordRepayment(customerId: 'cust-1', amountNaira: 8000);

    final customers = await firstValue(repo.watchCustomers());
    final cust1 = customers.firstWhere((c) => c.id == 'cust-1');

    expect(cust1.balance, -3000);
    expect(cust1.balance, isNot(0)); // the clamp-at-zero behavior this replaces
  });

  test(
    'recordCreditSale increases the balance and logs a creditSale transaction',
    () async {
      await repo.recordCreditSale(
        customerId: 'cust-3',
        amountNaira: 4000,
        saleId: 'sale-1',
      );

      final customers = await firstValue(repo.watchCustomers());
      expect(customers.firstWhere((c) => c.id == 'cust-3').balance, 4000);

      final transactions = await firstValue(repo.watchTransactions('cust-3'));
      expect(transactions, hasLength(1));
      expect(transactions.single.type, CustomerTransactionType.creditSale);
      expect(transactions.single.amountNaira, 4000);
      expect(transactions.single.balanceAfter, 4000);
      expect(transactions.single.saleId, 'sale-1');
    },
  );

  test('a manual "Record sale" (no saleId) still logs correctly', () async {
    await repo.recordCreditSale(customerId: 'cust-3', amountNaira: 2000);
    final transactions = await firstValue(repo.watchTransactions('cust-3'));
    expect(transactions.single.saleId, isNull);
  });

  test('createCustomer starts at a zero balance and shows up in watchCustomers', () async {
    final created = await repo.createCustomer(name: '  Tunde Bello  ', phone: ' 08099990000 ');

    expect(created.name, 'Tunde Bello'); // trimmed
    expect(created.phone, '08099990000'); // trimmed
    expect(created.balance, 0);

    final customers = await firstValue(repo.watchCustomers());
    expect(customers.any((c) => c.id == created.id && c.name == 'Tunde Bello'), isTrue);
  });

  test(
    'createCustomer with a nonzero openingBalanceNaira starts there and logs an '
    'openingBalance transaction, not a fabricated creditSale',
    () async {
      final created = await repo.createCustomer(
        name: 'Migrated Debtor',
        phone: '08033334444',
        openingBalanceNaira: 15000,
      );

      expect(created.balance, 15000);

      final transactions = await firstValue(repo.watchTransactions(created.id));
      expect(transactions, hasLength(1));
      expect(transactions.single.type, CustomerTransactionType.openingBalance);
      expect(transactions.single.amountNaira, 15000);
      expect(transactions.single.balanceAfter, 15000);
      expect(transactions.single.saleId, isNull);
    },
  );

  test('a newly created customer can immediately take a credit sale', () async {
    final created = await repo.createCustomer(name: 'Walk-in', phone: '08011112222');
    await repo.recordCreditSale(customerId: created.id, amountNaira: 6000, saleId: 'sale-9');

    final customers = await firstValue(repo.watchCustomers());
    expect(customers.firstWhere((c) => c.id == created.id).balance, 6000);
  });

  test('balance and history stay consistent across a mixed sequence', () async {
    await repo.recordCreditSale(customerId: 'cust-3', amountNaira: 10000);
    await repo.recordRepayment(customerId: 'cust-3', amountNaira: 4000);
    await repo.recordRepayment(
      customerId: 'cust-3',
      amountNaira: 8000,
    ); // overshoots into credit

    final customers = await firstValue(repo.watchCustomers());
    expect(customers.firstWhere((c) => c.id == 'cust-3').balance, -2000);

    final transactions = await firstValue(repo.watchTransactions('cust-3'));
    expect(transactions.map((t) => t.balanceAfter).toList(), [
      10000,
      6000,
      -2000,
    ]);
  });
}
