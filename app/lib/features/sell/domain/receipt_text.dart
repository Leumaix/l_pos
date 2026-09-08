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
    ..writeln('Total: ${_naira(sale.total)}');

  // One line per non-cash payment line — itemized by method, the only
  // shape that stays correct for both a single-method sale and a real
  // split — then cash received/change (already summed across however
  // many cash lines exist) whenever either is nonzero. Mirrors
  // receipt_screen.dart's _paymentRows exactly.
  for (final line in sale.payments) {
    if (line.method == PaymentMethod.cash) continue;
    buffer.writeln('${_paymentMethodLabel(line.method)}: ${_naira(line.amountNaira)}');
    if (line.method == PaymentMethod.customerAccount) {
      buffer.writeln('Charged to: ${line.customerName ?? ''}');
    }
  }
  if (sale.cashReceivedNaira > 0) {
    buffer.writeln('Cash received: ${_naira(sale.cashReceivedNaira)}');
  }
  if (sale.changeGivenNaira > 0) {
    buffer.writeln('Change: ${_naira(sale.changeGivenNaira)}');
  }

  buffer.writeln('Served by ${sale.staffName}');

  return buffer.toString();
}
