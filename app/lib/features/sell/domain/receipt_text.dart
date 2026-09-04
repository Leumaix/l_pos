import 'package:intl/intl.dart';

import 'cart_line.dart';
import 'sale.dart';

String _paymentMethodLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Cash',
  PaymentMethod.card => 'Card',
  PaymentMethod.transfer => 'Transfer',
  PaymentMethod.customerAccount => 'Customer Account',
};

String _naira(int amount) =>
    NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0).format(amount);

/// Plain-text receipt for the Share action — a POS terminal has no
/// printer yet, so this is what gets shared/sent instead.
String formatReceiptText(Sale sale, {required String businessName}) {
  final buffer = StringBuffer()
    ..writeln(businessName)
    ..writeln('Receipt #${sale.receiptNumber}')
    ..writeln(DateFormat('d MMM yyyy, h:mm a').format(sale.createdAt))
    ..writeln('------------------------------');

  for (final line in sale.items) {
    final detail = switch (line) {
      ProductCartLine(quantity: final qty) when qty > 1 => ' x$qty',
      _ => '',
    };
    buffer.writeln('${line.name}$detail — ${_naira(line.lineTotal)}');
  }

  buffer
    ..writeln('------------------------------')
    ..writeln('Subtotal: ${_naira(sale.subtotal)}')
    ..writeln('Total: ${_naira(sale.total)}')
    ..writeln('Payment: ${_paymentMethodLabel(sale.method)}');

  if (sale.method == PaymentMethod.cash) {
    buffer
      ..writeln('Cash received: ${_naira(sale.cashGiven ?? 0)}')
      ..writeln('Change: ${_naira(sale.changeGiven ?? 0)}');
  }
  if (sale.method == PaymentMethod.customerAccount) {
    buffer.writeln('Charged to: ${sale.customerName ?? ''}');
  }

  buffer.writeln('Served by ${sale.staffName}');

  return buffer.toString();
}
