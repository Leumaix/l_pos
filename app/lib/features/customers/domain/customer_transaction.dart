/// A credit sale or repayment moves a balance during normal operation;
/// openingBalance is different — a one-time starting figure set only
/// when an owner adds a customer with existing debt (e.g. migrating
/// debtors from a previous system), never a real sale or payment.
enum CustomerTransactionType { creditSale, repayment, openingBalance }

/// One entry in a customer's running history. [amountNaira] is always
/// positive; [type] carries the sign's meaning (creditSale and
/// openingBalance increase balance, repayment decreases it). A credit
/// sale made through the full POS checkout carries [saleId]; one
/// recorded directly from Customer detail (no cart/stock involved) does
/// not, and neither does an openingBalance entry.
class CustomerTransaction {
  final String id;
  final CustomerTransactionType type;
  final int amountNaira;
  final int balanceAfter;
  final DateTime createdAt;
  final String? saleId;

  const CustomerTransaction({
    required this.id,
    required this.type,
    required this.amountNaira,
    required this.balanceAfter,
    required this.createdAt,
    this.saleId,
  });
}
