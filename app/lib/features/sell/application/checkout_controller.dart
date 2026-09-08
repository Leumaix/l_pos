import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../customers/domain/customer.dart';
import '../domain/cart_line.dart';
import '../domain/checkout.dart';
import '../domain/sale.dart';
import 'cart_controller.dart';
import 'checkout_providers.dart';
import 'last_sale_provider.dart';

/// Turns a validated cart into a committed [Sale]. This is the only place
/// stock, customer balances, or the sales log actually change — adding
/// items to the cart (see cart_controller.dart) only ever checks against
/// reserved/tentative quantities and never mutates real inventory. If a
/// sale is abandoned before this runs, nothing here has happened yet, so
/// nothing needs to be undone.
///
/// [completeSale] builds the [Sale] record, then hands every mutation it
/// implies (gas deduction, product decrements, the customer credit, the
/// sale record) to CheckoutRepository.commitSale as ONE atomic write —
/// see checkout_repository.dart for why that lives there rather than
/// here as a sequence of separate repository calls.
class CheckoutController {
  final Ref ref;

  CheckoutController(this.ref);

  Future<Sale> completeSale({required PaymentMethod method, int? cashGiven, Customer? customer}) async {
    final cart = ref.read(cartControllerProvider);
    final staff = ref.read(authStateProvider).valueOrNull;
    if (staff == null) {
      throw StateError('completeSale called with no signed-in staff member');
    }

    final checkout = ref.read(checkoutRepositoryProvider);
    final now = DateTime.now();
    final sale = buildSale(
      cart: cart,
      payments: _paymentsFor(
        method: method,
        cartTotal: cart.total,
        cashGiven: cashGiven,
        customer: customer,
      ),
      staffId: staff.uid,
      staffName: staff.name,
      id: checkout.newSaleId(),
      receiptNumber: _receiptNumberFor(now),
      createdAt: now,
    );

    final gasUnits = cart.lines
        .whereType<GasCartLine>()
        .fold(0, (sum, line) => sum + line.unitsDeducted);

    await checkout.commitSale(sale: sale, gasUnitsDeducted: gasUnits);

    ref.read(cartControllerProvider.notifier).clear();
    ref.read(lastSaleProvider.notifier).state = sale;

    return sale;
  }

  /// Translates the single-method inputs the current Payment screen still
  /// collects into the [PaymentLine] list buildSale actually needs — the
  /// UI for entering a real split or a cross-method change is a separate,
  /// later follow-up (see the split-tender design doc's own §5), so this
  /// is the one place that bridges "what the screen collects today" and
  /// "what the domain layer now models." A cash overpayment becomes two
  /// lines (the amount tendered, then a negative change line) exactly the
  /// way FirebaseSalesRepository reads an old single-method sale doc back
  /// into this same shape — same mapping, same reasoning, so a sale built
  /// today and a pre-migration sale read back later produce identical
  /// [Sale.payments] shapes for the same real-world transaction.
  List<PaymentLine> _paymentsFor({
    required PaymentMethod method,
    required int cartTotal,
    int? cashGiven,
    Customer? customer,
  }) {
    switch (method) {
      case PaymentMethod.cash:
        final given = cashGiven ?? 0;
        final change = given - cartTotal;
        return [
          PaymentLine(method: PaymentMethod.cash, amountNaira: given),
          if (change > 0) PaymentLine(method: PaymentMethod.cash, amountNaira: -change),
        ];
      case PaymentMethod.card:
      case PaymentMethod.transfer:
        return [PaymentLine(method: method, amountNaira: cartTotal)];
      case PaymentMethod.customerAccount:
        return [
          PaymentLine(
            method: PaymentMethod.customerAccount,
            amountNaira: cartTotal,
            customerId: customer?.id,
            customerName: customer?.name,
          ),
        ];
    }
  }

  String _receiptNumberFor(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${time.year}${two(time.month)}${two(time.day)}';
    final clock = '${two(time.hour)}${two(time.minute)}${two(time.second)}';
    return '$date-$clock-${(time.microsecond % 1000).toString().padLeft(3, '0')}';
  }
}

final checkoutControllerProvider = Provider((ref) => CheckoutController(ref));
