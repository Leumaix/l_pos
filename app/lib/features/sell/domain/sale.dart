import 'cart_line.dart';

enum PaymentMethod { cash, card, transfer, customerAccount }

/// One line of a (possibly split) payment. [amountNaira] is signed and
/// always real money that actually moved through [method] — never "the
/// portion of the total this line covers" as a separate concept from
/// what was actually tendered. A [transfer] line of 5000 against a 4500
/// sale means the customer really transferred ₦5,000; the difference is
/// a SEPARATE line, not folded into this one.
///
/// Only a [PaymentMethod.cash] line may ever have a negative
/// [amountNaira] — that's how change given back is represented, on ANY
/// overpaid method, not just cash. Change is always physical cash handed
/// back right now: a card "refund" is a delayed bank operation, not an
/// instant checkout event, and a negative [PaymentMethod.customerAccount]
/// line would mean un-charging a customer's balance as a side effect of
/// giving change — a materially different, much worse problem than this
/// class is meant to represent. See [Sale.changeGivenNaira].
///
/// [customerId]/[customerName] are set only when [method] is
/// [PaymentMethod.customerAccount] — see [Sale.customerAccountLine] for
/// the at-most-one-per-sale invariant [buildSale] enforces.
class PaymentLine {
  final PaymentMethod method;
  final int amountNaira;
  final String? customerId;
  final String? customerName;

  const PaymentLine({
    required this.method,
    required this.amountNaira,
    this.customerId,
    this.customerName,
  });
}

/// A completed sale — the durable record of a checkout, and what the
/// Receipt screen and Reports read from. [items] is the exact cart
/// snapshot at the moment of sale, not a live reference.
///
/// [total] is computed from [items] at build time (see [buildSale]),
/// completely independent of [payments] — that independence is what
/// makes "do the payments actually add up to the total" a real,
/// meaningful check rather than a tautology definitionally guaranteed to
/// pass. [payments] is the ONE source of truth for how a sale was paid;
/// there is no separate method/cashGiven/changeGiven/customerId on this
/// class the way there used to be when every sale had exactly one
/// payment line — a single-method sale is now just the common case of a
/// one-element [payments] list, not a structurally different shape.
class Sale {
  final String id;
  final String receiptNumber;
  final List<CartLine> items;
  final int subtotal;
  final int total;
  final List<PaymentLine> payments;
  final String staffId;
  final String staffName;
  final DateTime createdAt;

  const Sale({
    required this.id,
    required this.receiptNumber,
    required this.items,
    required this.subtotal,
    required this.total,
    required this.payments,
    required this.staffId,
    required this.staffName,
    required this.createdAt,
  });

  /// The one payment line charged to a customer's account, if any —
  /// [buildSale] enforces at most one per sale (see
  /// MultipleCustomerAccountLinesException), so this is a real,
  /// meaningful lookup rather than "the first of possibly several."
  /// Convenience for callers (the checkout commit, the receipt) that
  /// need "was any of this charged to a customer" without repeating the
  /// scan themselves.
  PaymentLine? get customerAccountLine {
    for (final line in payments) {
      if (line.method == PaymentMethod.customerAccount) return line;
    }
    return null;
  }

  /// Cash physically received — the positive cash-tagged lines only; see
  /// [changeGivenNaira] for cash that went back OUT. Derived, never
  /// stored: recomputing from [payments] on every read is what
  /// guarantees this can never drift from what the sale actually says,
  /// the same reasoning kgRemaining in the gas_stock package is always
  /// computed fresh rather than cached.
  int get cashReceivedNaira => payments
      .where((p) => p.method == PaymentMethod.cash && p.amountNaira > 0)
      .fold(0, (sum, p) => sum + p.amountNaira);

  /// Cash handed back as change — whether it came from a cash
  /// overpayment (the original, familiar case) or a non-cash one
  /// (transfer/card, cash change). Always the negative cash-method
  /// lines' combined magnitude; see [PaymentLine]'s own doc comment for
  /// why only cash may ever be negative.
  int get changeGivenNaira => payments
      .where((p) => p.method == PaymentMethod.cash && p.amountNaira < 0)
      .fold(0, (sum, p) => sum + -p.amountNaira);
}
