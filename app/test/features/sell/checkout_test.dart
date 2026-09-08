import 'package:flutter_test/flutter_test.dart';
import 'package:gas_stock/gas_stock.dart';
import 'package:leumadepos/features/sell/domain/cart.dart';
import 'package:leumadepos/features/sell/domain/checkout.dart';
import 'package:leumadepos/features/sell/domain/product.dart';
import 'package:leumadepos/features/sell/domain/sale.dart';

void main() {
  const cylinder = Product(
    id: 'cyl-6kg',
    categoryId: 'cat-cylinders',
    name: '6kg Cylinder',
    price: 15000,
    stockCount: 9,
  );
  final createdAt = DateTime(2026, 9, 2, 12, 0);

  Cart cartWithProduct() =>
      addProduct(const Cart(), cylinder, lineId: 'l1').cart; // total 15000

  Sale build({required Cart cart, required List<PaymentLine> payments}) {
    return buildSale(
      cart: cart,
      payments: payments,
      staffId: 'staff-1',
      staffName: 'Ifeoma',
      id: 'sale-1',
      receiptNumber: 'R-1',
      createdAt: createdAt,
    );
  }

  group('empty cart', () {
    test('throws EmptyCartException regardless of payments', () {
      expect(
        () => build(
          cart: const Cart(),
          payments: const [PaymentLine(method: PaymentMethod.card, amountNaira: 0)],
        ),
        throwsA(isA<EmptyCartException>()),
      );
    });
  });

  group('single-method sale — the common case, still a one-element payments list', () {
    test('exact cash, no change: a single cash line', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [PaymentLine(method: PaymentMethod.cash, amountNaira: 15000)],
      );
      expect(sale.payments, hasLength(1));
      expect(sale.cashReceivedNaira, 15000);
      expect(sale.changeGivenNaira, 0);
    });

    test('cash above total: tendered line plus a negative change line, still sums to total', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [
          PaymentLine(method: PaymentMethod.cash, amountNaira: 20000),
          PaymentLine(method: PaymentMethod.cash, amountNaira: -5000),
        ],
      );
      expect(sale.cashReceivedNaira, 20000);
      expect(sale.changeGivenNaira, 5000);
      expect(sale.total, 15000);
    });

    test('card needs no customer/change, one line at the total', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [PaymentLine(method: PaymentMethod.card, amountNaira: 15000)],
      );
      expect(sale.total, 15000);
      expect(sale.customerAccountLine, isNull);
      expect(sale.changeGivenNaira, 0);
    });

    test('transfer behaves the same as card', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [PaymentLine(method: PaymentMethod.transfer, amountNaira: 15000)],
      );
      expect(sale.total, 15000);
      expect(sale.customerAccountLine, isNull);
    });

    test('customerAccount records the customer on its line', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [
          PaymentLine(
            method: PaymentMethod.customerAccount,
            amountNaira: 15000,
            customerId: 'cust-1',
            customerName: 'Ngozi Eze',
          ),
        ],
      );
      expect(sale.customerAccountLine?.customerId, 'cust-1');
      expect(sale.customerAccountLine?.customerName, 'Ngozi Eze');
    });

    test('throws CustomerRequiredException for a customerAccount line with no customerId', () {
      expect(
        () => build(
          cart: cartWithProduct(),
          payments: const [PaymentLine(method: PaymentMethod.customerAccount, amountNaira: 15000)],
        ),
        throwsA(isA<CustomerRequiredException>()),
      );
    });
  });

  group('split-tender', () {
    test('exact split across two methods, no change', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [
          PaymentLine(method: PaymentMethod.card, amountNaira: 10000),
          PaymentLine(method: PaymentMethod.cash, amountNaira: 5000),
        ],
      );
      expect(sale.payments, hasLength(2));
      expect(sale.cashReceivedNaira, 5000);
      expect(sale.changeGivenNaira, 0);
      expect(sale.total, 15000);
    });

    test('overpay by transfer, cash change — the exact new scenario this feature adds', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [
          PaymentLine(method: PaymentMethod.transfer, amountNaira: 20000),
          PaymentLine(method: PaymentMethod.cash, amountNaira: -5000),
        ],
      );
      expect(sale.total, 15000);
      expect(sale.cashReceivedNaira, 0); // no cash was RECEIVED, only paid out
      expect(sale.changeGivenNaira, 5000);
    });

    test('split plus change on top: card + cash received + cash change, all composing correctly', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [
          PaymentLine(method: PaymentMethod.card, amountNaira: 10000),
          PaymentLine(method: PaymentMethod.cash, amountNaira: 6000),
          PaymentLine(method: PaymentMethod.cash, amountNaira: -1000),
        ],
      );
      expect(sale.total, 15000);
      expect(sale.cashReceivedNaira, 6000);
      expect(sale.changeGivenNaira, 1000);
    });

    test('a split including a customerAccount line for less than the full total', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [
          PaymentLine(
            method: PaymentMethod.customerAccount,
            amountNaira: 5000,
            customerId: 'cust-1',
            customerName: 'Ngozi Eze',
          ),
          PaymentLine(method: PaymentMethod.cash, amountNaira: 10000),
        ],
      );
      expect(sale.customerAccountLine?.amountNaira, 5000);
      expect(sale.cashReceivedNaira, 10000);
    });

    test('throws PaymentsDoNotMatchTotalException when the lines sum short of the total', () {
      expect(
        () => build(
          cart: cartWithProduct(),
          payments: const [PaymentLine(method: PaymentMethod.cash, amountNaira: 10000)],
        ),
        throwsA(
          isA<PaymentsDoNotMatchTotalException>()
              .having((e) => e.total, 'total', 15000)
              .having((e) => e.paymentsSum, 'paymentsSum', 10000),
        ),
      );
    });

    test('throws PaymentsDoNotMatchTotalException when the lines sum over the total with no change line', () {
      expect(
        () => build(
          cart: cartWithProduct(),
          payments: const [PaymentLine(method: PaymentMethod.transfer, amountNaira: 20000)],
        ),
        throwsA(isA<PaymentsDoNotMatchTotalException>()),
      );
    });

    test('throws InvalidPaymentLineException for a negative card line — only cash may ever be negative', () {
      expect(
        () => build(
          cart: cartWithProduct(),
          payments: const [
            PaymentLine(method: PaymentMethod.transfer, amountNaira: 20000),
            PaymentLine(method: PaymentMethod.card, amountNaira: -5000),
          ],
        ),
        throwsA(isA<InvalidPaymentLineException>()),
      );
    });

    test('throws InvalidPaymentLineException for a zero-amount line', () {
      expect(
        () => build(
          cart: cartWithProduct(),
          payments: const [
            PaymentLine(method: PaymentMethod.cash, amountNaira: 15000),
            PaymentLine(method: PaymentMethod.card, amountNaira: 0),
          ],
        ),
        throwsA(isA<InvalidPaymentLineException>()),
      );
    });

    test('throws MultipleCustomerAccountLinesException for two customerAccount lines', () {
      expect(
        () => build(
          cart: cartWithProduct(),
          payments: const [
            PaymentLine(
              method: PaymentMethod.customerAccount,
              amountNaira: 10000,
              customerId: 'cust-1',
              customerName: 'Ngozi Eze',
            ),
            PaymentLine(
              method: PaymentMethod.customerAccount,
              amountNaira: 5000,
              customerId: 'cust-2',
              customerName: 'Chidi Okafor',
            ),
          ],
        ),
        throwsA(isA<MultipleCustomerAccountLinesException>()),
      );
    });

    test('throws TooManyPaymentLinesException past kMaxPaymentLines', () {
      expect(
        () => build(
          cart: cartWithProduct(),
          payments: List.generate(
            kMaxPaymentLines + 1,
            (i) => PaymentLine(method: PaymentMethod.cash, amountNaira: i.isEven ? 1 : -1),
          ),
        ),
        throwsA(isA<TooManyPaymentLinesException>()),
      );
    });
  });

  group('sale snapshot integrity', () {
    test('items/subtotal/total mirror the cart at build time', () {
      var cart = addProduct(const Cart(), cylinder, lineId: 'l1').cart;
      cart = addGasByAmount(
        cart,
        amountNaira: 5000,
        currentGasStock: const GasStock(28000),
        lineId: 'g1',
      ).cart;

      final sale = build(
        cart: cart,
        payments: [PaymentLine(method: PaymentMethod.card, amountNaira: cart.total)],
      );

      expect(sale.items, hasLength(2));
      expect(sale.subtotal, 20000);
      expect(sale.total, 20000);
    });

    test('carries through staff attribution and identifiers verbatim', () {
      final sale = build(
        cart: cartWithProduct(),
        payments: const [PaymentLine(method: PaymentMethod.card, amountNaira: 15000)],
      );
      expect(sale.staffId, 'staff-1');
      expect(sale.staffName, 'Ifeoma');
      expect(sale.id, 'sale-1');
      expect(sale.receiptNumber, 'R-1');
      expect(sale.createdAt, createdAt);
    });
  });
}
