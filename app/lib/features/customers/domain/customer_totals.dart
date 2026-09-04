import 'customer.dart';

/// Total owed to the business across all customers. A negative balance is
/// store credit (the business owes the customer), not a debt — it's
/// excluded here rather than netted against what others owe, since the
/// two aren't the same kind of obligation.
///
/// This is the one place this figure is computed. Home, the Customers
/// list banner, and Reports' debtors banner all call this rather than
/// summing balances themselves, so the three can never drift apart.
int totalOwedByCustomers(List<Customer> customers) {
  return customers.fold(0, (sum, c) => sum + (c.balance > 0 ? c.balance : 0));
}
