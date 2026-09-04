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
      method: method,
      staffId: staff.uid,
      staffName: staff.name,
      id: checkout.newSaleId(),
      receiptNumber: _receiptNumberFor(now),
      createdAt: now,
      cashGiven: cashGiven,
      customer: customer,
    );

    final gasUnits = cart.lines
        .whereType<GasCartLine>()
        .fold(0, (sum, line) => sum + line.unitsDeducted);

    await checkout.commitSale(sale: sale, gasUnitsDeducted: gasUnits);

    ref.read(cartControllerProvider.notifier).clear();
    ref.read(lastSaleProvider.notifier).state = sale;

    return sale;
  }

  String _receiptNumberFor(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${time.year}${two(time.month)}${two(time.day)}';
    final clock = '${two(time.hour)}${two(time.minute)}${two(time.second)}';
    return '$date-$clock-${(time.microsecond % 1000).toString().padLeft(3, '0')}';
  }
}

final checkoutControllerProvider = Provider((ref) => CheckoutController(ref));
