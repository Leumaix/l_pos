import 'dart:async';

import '../../../core/utils/replay_stream.dart';
import '../domain/customer.dart';
import '../domain/customer_transaction.dart';

abstract class CustomerRepository {
  Stream<List<Customer>> watchCustomers();
  Stream<List<CustomerTransaction>> watchTransactions(String customerId);

  /// Creates a brand-new customer. Any active staff member can do this
  /// at the default zero starting balance — a walk-in with no prior
  /// record, added on the spot (e.g. mid credit sale). A nonzero
  /// [openingBalanceNaira] (migrating an existing debtor's balance from
  /// elsewhere) is owner-only, enforced server-side by
  /// firestore.rules' /customers create rule — the Payment screen's
  /// inline creation path never passes one, regardless of role.
  Future<Customer> createCustomer({
    required String name,
    required String phone,
    int openingBalanceNaira = 0,
  });

  /// Adds [amountNaira] to a customer's balance — the effect of a credit
  /// sale. Called only from the checkout commit step (with [saleId] set)
  /// or from Customer detail's "Record sale" shortcut (no cart/stock
  /// involved, [saleId] null) — never speculatively.
  Future<void> recordCreditSale({
    required String customerId,
    required int amountNaira,
    String? saleId,
  });

  /// Subtracts [amountNaira] from a customer's balance. Allowed to take
  /// the balance negative — a repayment larger than what's owed becomes
  /// store credit, it's never clamped at zero.
  Future<void> recordRepayment({required String customerId, required int amountNaira});
}

/// Seed customers — placeholder data for development only, same as
/// FakeInventoryRepository's catalog. Real customers come from the
/// business once Firestore is set up.
class FakeCustomerRepository implements CustomerRepository {
  List<Customer> _customers = const [
    Customer(id: 'cust-1', name: 'Ngozi Eze', phone: '08051112222', balance: 5000),
    Customer(id: 'cust-2', name: 'Emeka Okafor', phone: '08063334444', balance: 13000),
    Customer(id: 'cust-3', name: 'Blessing Adeyemi', phone: '08077778888', balance: 0),
  ];
  final _customersController = StreamController<List<Customer>>.broadcast();

  final Map<String, List<CustomerTransaction>> _transactions = {};
  final _transactionsController = StreamController<void>.broadcast();

  int _txCounter = 0;
  String _newTransactionId() => 'ctx-${_txCounter++}';

  int _customerCounter = 0;

  @override
  Stream<List<Customer>> watchCustomers() =>
      replayLatest(() => _customers, _customersController.stream);

  @override
  Future<Customer> createCustomer({
    required String name,
    required String phone,
    int openingBalanceNaira = 0,
  }) async {
    final customer = Customer(
      id: 'cust-fake-${_customerCounter++}',
      name: name.trim(),
      phone: phone.trim(),
      balance: openingBalanceNaira,
    );
    _customers = [..._customers, customer];
    _customersController.add(_customers);
    if (openingBalanceNaira != 0) {
      _transactions
          .putIfAbsent(customer.id, () => [])
          .add(
            CustomerTransaction(
              id: _newTransactionId(),
              type: CustomerTransactionType.openingBalance,
              amountNaira: openingBalanceNaira.abs(),
              balanceAfter: openingBalanceNaira,
              createdAt: DateTime.now(),
            ),
          );
      _transactionsController.add(null);
    }
    return customer;
  }

  @override
  Stream<List<CustomerTransaction>> watchTransactions(String customerId) {
    List<CustomerTransaction> current() =>
        List.unmodifiable(_transactions[customerId] ?? const []);
    return replayLatest(current, _transactionsController.stream.map((_) => current()));
  }

  Future<void> _applyBalanceChange(
    String customerId,
    int delta,
    CustomerTransactionType type, {
    String? saleId,
  }) async {
    final index = _customers.indexWhere((c) => c.id == customerId);
    if (index == -1) {
      throw ArgumentError.value(customerId, 'customerId', 'no such customer');
    }

    final updated = _customers[index].copyWith(balance: _customers[index].balance + delta);
    _customers = [for (final c in _customers) if (c.id == customerId) updated else c];
    _customersController.add(_customers);

    _transactions
        .putIfAbsent(customerId, () => [])
        .add(
          CustomerTransaction(
            id: _newTransactionId(),
            type: type,
            amountNaira: delta.abs(),
            balanceAfter: updated.balance,
            createdAt: DateTime.now(),
            saleId: saleId,
          ),
        );
    _transactionsController.add(null);
  }

  @override
  Future<void> recordCreditSale({
    required String customerId,
    required int amountNaira,
    String? saleId,
  }) {
    return _applyBalanceChange(
      customerId,
      amountNaira,
      CustomerTransactionType.creditSale,
      saleId: saleId,
    );
  }

  @override
  Future<void> recordRepayment({required String customerId, required int amountNaira}) {
    return _applyBalanceChange(customerId, -amountNaira, CustomerTransactionType.repayment);
  }
}
