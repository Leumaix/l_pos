import 'cart.dart';
import 'sale.dart';

/// The most payment lines a single sale may carry — 3 real tender
/// methods plus 1 change line comfortably fits, and nobody splits one
/// real sale across more than a few tenders in practice. Not an
/// arbitrary UX limitation: firestore.rules has no native sum/reduce
/// over a list, so validating "do the payments add up to the total"
/// server-side needs a bounded, indexable list to write a finite
/// expression against — this constant is the client-side half of that
/// same bound, enforced here first for a clean error instead of a later
/// rules rejection.
const kMaxPaymentLines = 4;

/// Thrown when [buildSale] is asked to check out an empty cart. The UI
/// should never let this happen (Go to payment is disabled on an empty
/// cart) — this is a defensive guard, not a normal-flow error path.
class EmptyCartException implements Exception {
  const EmptyCartException();
}

/// Thrown when [buildSale] is given more than [kMaxPaymentLines] payment
/// lines. Same defensive-guard reasoning as the others here — no real
/// checkout UI should ever be able to construct this many lines.
class TooManyPaymentLinesException implements Exception {
  final int count;
  const TooManyPaymentLinesException(this.count);
}

/// Thrown for a payment line that can never be legitimate on its own,
/// independent of the other lines in the split: a zero amount (meaningless
/// — nothing moved), or a negative amount on anything other than
/// [PaymentMethod.cash] (change is always physical cash; see
/// [PaymentLine]'s own doc comment for why).
class InvalidPaymentLineException implements Exception {
  final PaymentLine line;
  const InvalidPaymentLineException(this.line);
}

/// Thrown when more than one [PaymentMethod.customerAccount] line is
/// given — splitting one sale's credit portion across two different
/// customers isn't a real scenario, and would multiply the
/// customer-balance-pairing complexity in the checkout commit for no
/// reason. See [Sale.customerAccountLine].
class MultipleCustomerAccountLinesException implements Exception {
  const MultipleCustomerAccountLinesException();
}

/// Thrown for a [PaymentMethod.customerAccount] line with no customer
/// attached.
class CustomerRequiredException implements Exception {
  const CustomerRequiredException();
}

/// Thrown when the payment lines' amounts don't sum to the cart's total —
/// the one invariant every other check here exists to protect. Carries
/// both numbers (not just the difference) since the caller needs to know
/// which direction it's wrong to show a sensible message: [paymentsSum]
/// short of [total] is "still owed," short the other way is "overpaid
/// with no change line to account for it."
class PaymentsDoNotMatchTotalException implements Exception {
  final int total;
  final int paymentsSum;
  const PaymentsDoNotMatchTotalException({
    required this.total,
    required this.paymentsSum,
  });
}

/// Pure: validates and constructs the [Sale] record for a checkout, given
/// the cart and how it was paid — one or more [PaymentLine]s, which may
/// include a negative cash line representing change given back on an
/// overpayment (on any method, not just cash — see [PaymentLine]'s own
/// doc comment). A single-method sale with no change is simply a
/// one-element list; there is no separate "simple" code path.
///
/// Never mutates anything — see CheckoutController/CheckoutRepository
/// for the commit step (stock/customer-balance/sale persistence) that
/// only happens once this succeeds.
Sale buildSale({
  required Cart cart,
  required List<PaymentLine> payments,
  required String staffId,
  required String staffName,
  required String id,
  required String receiptNumber,
  required DateTime createdAt,
}) {
  if (cart.isEmpty) throw const EmptyCartException();
  if (payments.length > kMaxPaymentLines) {
    throw TooManyPaymentLinesException(payments.length);
  }

  for (final line in payments) {
    if (line.amountNaira == 0) throw InvalidPaymentLineException(line);
    if (line.amountNaira < 0 && line.method != PaymentMethod.cash) {
      throw InvalidPaymentLineException(line);
    }
  }

  final customerAccountLines = payments.where((p) => p.method == PaymentMethod.customerAccount);
  if (customerAccountLines.length > 1) {
    throw const MultipleCustomerAccountLinesException();
  }
  if (customerAccountLines.any((p) => p.customerId == null)) {
    throw const CustomerRequiredException();
  }

  final paymentsSum = payments.fold(0, (sum, p) => sum + p.amountNaira);
  if (paymentsSum != cart.total) {
    throw PaymentsDoNotMatchTotalException(total: cart.total, paymentsSum: paymentsSum);
  }

  return Sale(
    id: id,
    receiptNumber: receiptNumber,
    items: cart.lines,
    subtotal: cart.subtotal,
    total: cart.total,
    payments: payments,
    staffId: staffId,
    staffName: staffName,
    createdAt: createdAt,
  );
}
