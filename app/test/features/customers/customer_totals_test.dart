import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/customers/domain/customer.dart';
import 'package:leumadepos/features/customers/domain/customer_totals.dart';

Customer _c(int balance) =>
    Customer(id: 'x', name: 'X', phone: '0', balance: balance);

void main() {
  test('sums only positive balances', () {
    expect(totalOwedByCustomers([_c(5000), _c(13000), _c(0)]), 18000);
  });

  test(
    'excludes negative balances (store credit) rather than netting them',
    () {
      expect(totalOwedByCustomers([_c(5000), _c(-2000)]), 5000);
    },
  );

  test('empty list totals zero', () {
    expect(totalOwedByCustomers([]), 0);
  });

  test('all-negative balances total zero, not negative', () {
    expect(totalOwedByCustomers([_c(-1000), _c(-500)]), 0);
  });
}
