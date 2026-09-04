import '../../customers/domain/customer.dart';
import 'cart.dart';
import 'sale.dart';

/// Thrown when [buildSale] is asked to check out an empty cart. The UI
/// should never let this happen (Go to payment is disabled on an empty
/// cart) — this is a defensive guard, not a normal-flow error path.
class EmptyCartException implements Exception {
  const EmptyCartException();
}

/// Thrown for a cash sale where the amount tendered doesn't cover the
/// total. [shortfall] is how much more is needed. The UI should disable
/// "Complete sale" until this can't happen, same reasoning as above.
class InsufficientCashException implements Exception {
  final int shortfall;
  const InsufficientCashException(this.shortfall);
}

/// Thrown for a customer-account sale with no customer selected. Same
/// defensive-guard reasoning.
class CustomerRequiredException implements Exception {
  const CustomerRequiredException();
}

/// Pure: validates and constructs the [Sale] record for a checkout, given
/// the cart and the chosen payment method. Never mutates anything — see
/// CheckoutController for the commit step (stock/customer-balance/sale
/// persistence) that only happens once this succeeds.
Sale buildSale({
  required Cart cart,
  required PaymentMethod method,
  required String staffId,
  required String staffName,
  required String id,
  required String receiptNumber,
  required DateTime createdAt,
  int? cashGiven,
  Customer? customer,
}) {
  if (cart.isEmpty) throw const EmptyCartException();

  int? changeGiven;
  if (method == PaymentMethod.cash) {
    final given = cashGiven ?? 0;
    if (given < cart.total) {
      throw InsufficientCashException(cart.total - given);
    }
    changeGiven = given - cart.total;
  }

  if (method == PaymentMethod.customerAccount && customer == null) {
    throw const CustomerRequiredException();
  }

  return Sale(
    id: id,
    receiptNumber: receiptNumber,
    items: cart.lines,
    subtotal: cart.subtotal,
    total: cart.total,
    method: method,
    cashGiven: method == PaymentMethod.cash ? cashGiven : null,
    changeGiven: changeGiven,
    customerId: method == PaymentMethod.customerAccount ? customer!.id : null,
    customerName: method == PaymentMethod.customerAccount ? customer!.name : null,
    staffId: staffId,
    staffName: staffName,
    createdAt: createdAt,
  );
}
