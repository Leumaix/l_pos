import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/sell/domain/cart.dart';
import 'package:leumadepos/features/sell/domain/checkout.dart';
import 'package:leumadepos/features/sell/domain/product.dart';
import 'package:leumadepos/features/sell/domain/receipt_text.dart';
import 'package:leumadepos/features/sell/domain/sale.dart';

void main() {
  const cylinder = Product(
    id: 'cyl-6kg',
    categoryId: 'cat-cylinders',
    name: '6kg Cylinder',
    price: 15000,
    stockCount: 9,
  );

  Sale buildTestSale() {
    var cart = addProduct(const Cart(), cylinder, lineId: 'l1').cart;
    cart = addProduct(cart, cylinder, lineId: 'l2').cart; // quantity 2

    return buildSale(
      cart: cart,
      payments: const [
        PaymentLine(method: PaymentMethod.cash, amountNaira: 35000),
        PaymentLine(method: PaymentMethod.cash, amountNaira: -5000),
      ],
      staffId: 'staff-1',
      staffName: 'Ifeoma',
      id: 'sale-1',
      receiptNumber: 'R-1',
      createdAt: DateTime(2026, 9, 2, 14, 30),
    );
  }

  test('includes business name, receipt number, totals, and staff', () {
    final text = formatReceiptText(
      buildTestSale(),
      businessName: 'PH-Zazaa Oil & Gas',
    );

    expect(text, contains('PH-Zazaa Oil & Gas'));
    expect(text, contains('R-1'));
    expect(text, contains('₦30,000')); // 2 x ₦15,000
    expect(text, contains('Served by Ifeoma'));
  });

  test('shows quantity for a merged product line', () {
    final text = formatReceiptText(
      buildTestSale(),
      businessName: 'PH-Zazaa Oil & Gas',
    );
    expect(text, contains('6kg Cylinder x2'));
  });

  test('shows cash received and change for a cash sale', () {
    final text = formatReceiptText(
      buildTestSale(),
      businessName: 'PH-Zazaa Oil & Gas',
    );
    expect(text, contains('Cash received: ₦35,000'));
    expect(text, contains('Change: ₦5,000'));
  });

  test(
    'shows the customer name for a customer-account sale, no cash lines',
    () {
      var cart = addProduct(const Cart(), cylinder, lineId: 'l1').cart;
      final sale = buildSale(
        cart: cart,
        payments: [
          PaymentLine(
            method: PaymentMethod.customerAccount,
            amountNaira: cart.total,
            customerId: 'cust-1',
            customerName: 'Ngozi Eze',
          ),
        ],
        staffId: 'staff-1',
        staffName: 'Ifeoma',
        id: 'sale-2',
        receiptNumber: 'R-2',
        createdAt: DateTime(2026, 9, 2, 14, 30),
      );

      final text = formatReceiptText(sale, businessName: 'PH-Zazaa Oil & Gas');
      expect(text, contains('Charged to: Ngozi Eze'));
      expect(text, isNot(contains('Cash received')));
    },
  );
}
