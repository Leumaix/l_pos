import 'package:flutter_test/flutter_test.dart';
import 'package:gas_stock/gas_stock.dart';
import 'package:leumadepos/features/customers/domain/customer.dart';
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
  const customer = Customer(
    id: 'cust-1',
    name: 'Ngozi Eze',
    phone: '08051112222',
    balance: 5000,
  );
  final createdAt = DateTime(2026, 9, 2, 12, 0);

  Cart cartWithProduct() =>
      addProduct(const Cart(), cylinder, lineId: 'l1').cart; // total 15000

  Sale build({
    required Cart cart,
    required PaymentMethod method,
    int? cashGiven,
    Customer? customer,
  }) {
    return buildSale(
      cart: cart,
      method: method,
      staffId: 'staff-1',
      staffName: 'Ifeoma',
      id: 'sale-1',
      receiptNumber: 'R-1',
      createdAt: createdAt,
      cashGiven: cashGiven,
      customer: customer,
    );
  }

  group('empty cart', () {
    test('throws EmptyCartException regardless of method', () {
      expect(
        () => build(cart: const Cart(), method: PaymentMethod.card),
        throwsA(isA<EmptyCartException>()),
      );
    });
  });

  group('cash', () {
    test('exact cash given produces zero change', () {
      final sale = build(
        cart: cartWithProduct(),
        method: PaymentMethod.cash,
        cashGiven: 15000,
      );
      expect(sale.cashGiven, 15000);
      expect(sale.changeGiven, 0);
    });

    test('cash above total produces positive change', () {
      final sale = build(
        cart: cartWithProduct(),
        method: PaymentMethod.cash,
        cashGiven: 20000,
      );
      expect(sale.changeGiven, 5000);
    });

    test(
      'cash below total throws InsufficientCashException with the shortfall',
      () {
        expect(
          () => build(
            cart: cartWithProduct(),
            method: PaymentMethod.cash,
            cashGiven: 10000,
          ),
          throwsA(
            isA<InsufficientCashException>().having(
              (e) => e.shortfall,
              'shortfall',
              5000,
            ),
          ),
        );
      },
    );

    test('no cash given at all is treated as zero and throws', () {
      expect(
        () => build(cart: cartWithProduct(), method: PaymentMethod.cash),
        throwsA(isA<InsufficientCashException>()),
      );
    });
  });

  group('card / transfer', () {
    test('card needs no cash/customer and produces no change field', () {
      final sale = build(cart: cartWithProduct(), method: PaymentMethod.card);
      expect(sale.cashGiven, isNull);
      expect(sale.changeGiven, isNull);
      expect(sale.total, 15000);
    });

    test('transfer behaves the same as card', () {
      final sale = build(
        cart: cartWithProduct(),
        method: PaymentMethod.transfer,
      );
      expect(sale.total, 15000);
      expect(sale.customerId, isNull);
    });
  });

  group('customer account', () {
    test('throws CustomerRequiredException when no customer is given', () {
      expect(
        () => build(
          cart: cartWithProduct(),
          method: PaymentMethod.customerAccount,
        ),
        throwsA(isA<CustomerRequiredException>()),
      );
    });

    test('records the customer id/name on the sale, no cash fields', () {
      final sale = build(
        cart: cartWithProduct(),
        method: PaymentMethod.customerAccount,
        customer: customer,
      );
      expect(sale.customerId, 'cust-1');
      expect(sale.customerName, 'Ngozi Eze');
      expect(sale.cashGiven, isNull);
      expect(sale.changeGiven, isNull);
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

      final sale = build(cart: cart, method: PaymentMethod.card);

      expect(sale.items, hasLength(2));
      expect(sale.subtotal, 20000);
      expect(sale.total, 20000);
    });

    test('carries through staff attribution and identifiers verbatim', () {
      final sale = build(cart: cartWithProduct(), method: PaymentMethod.card);
      expect(sale.staffId, 'staff-1');
      expect(sale.staffName, 'Ifeoma');
      expect(sale.id, 'sale-1');
      expect(sale.receiptNumber, 'R-1');
      expect(sale.createdAt, createdAt);
    });
  });
}
