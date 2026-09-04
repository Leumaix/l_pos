import 'cart_line.dart';

enum PaymentMethod { cash, card, transfer, customerAccount }

/// A completed sale — the durable record of a checkout, and what the
/// Receipt screen and (later) Reports read from. [items] is the exact
/// cart snapshot at the moment of sale, not a live reference.
class Sale {
  final String id;
  final String receiptNumber;
  final List<CartLine> items;
  final int subtotal;
  final int total;
  final PaymentMethod method;
  final int? cashGiven; // set only for PaymentMethod.cash
  final int? changeGiven; // set only for PaymentMethod.cash
  final String? customerId; // set only for PaymentMethod.customerAccount
  final String? customerName; // set only for PaymentMethod.customerAccount
  final String staffId;
  final String staffName;
  final DateTime createdAt;

  const Sale({
    required this.id,
    required this.receiptNumber,
    required this.items,
    required this.subtotal,
    required this.total,
    required this.method,
    required this.staffId,
    required this.staffName,
    required this.createdAt,
    this.cashGiven,
    this.changeGiven,
    this.customerId,
    this.customerName,
  });
}
