import 'package:flutter_test/flutter_test.dart';
import 'package:gas_stock/gas_stock.dart';
import 'package:leumadepos/features/reports/domain/sales_report.dart';
import 'package:leumadepos/features/sell/domain/cart.dart';
import 'package:leumadepos/features/sell/domain/checkout.dart';
import 'package:leumadepos/features/sell/domain/product.dart';
import 'package:leumadepos/features/sell/domain/sale.dart';

const _cylinder = Product(
  id: 'cyl-6kg',
  categoryId: 'cat-cylinders',
  name: '6kg Cylinder',
  price: 15000,
  stockCount: 9,
);
const _lighter = Product(
  id: 'acc-lighter',
  categoryId: 'cat-accessories',
  name: 'Lighter',
  price: 300,
  stockCount: 50,
);

Sale _saleAt(
  DateTime when, {
  int gasAmount = 0,
  bool cylinderLine = false,
  bool accessoryLine = false,
}) {
  var cart = const Cart();
  if (gasAmount > 0) {
    cart = addGasByAmount(
      cart,
      amountNaira: gasAmount,
      currentGasStock: const GasStock(1000000),
      lineId: 'gas',
    ).cart;
  }
  if (cylinderLine) cart = addProduct(cart, _cylinder, lineId: 'cyl').cart;
  if (accessoryLine) cart = addProduct(cart, _lighter, lineId: 'acc').cart;

  return buildSale(
    cart: cart,
    payments: [PaymentLine(method: PaymentMethod.cash, amountNaira: cart.total)],
    staffId: 's1',
    staffName: 'Staff',
    id: 'sale-${when.millisecondsSinceEpoch}',
    receiptNumber: 'R',
    createdAt: when,
  );
}

void main() {
  final now = DateTime(2026, 9, 10, 15, 0); // a Thursday

  group('range filtering', () {
    test('today only includes sales from the same calendar day', () {
      final sales = [
        _saleAt(DateTime(2026, 9, 10, 8, 0), gasAmount: 1000), // today, earlier
        _saleAt(DateTime(2026, 9, 9, 23, 59), gasAmount: 2000), // yesterday
      ];
      final report = buildSalesReport(
        sales,
        range: ReportRange.today,
        now: now,
      );
      expect(report.totalForRange, 1000);
    });

    test('week includes the last 7 days inclusive of today', () {
      final sales = [
        _saleAt(now, gasAmount: 1000),
        _saleAt(
          now.subtract(const Duration(days: 6)),
          gasAmount: 2000,
        ), // exactly 6 days ago: in range
        _saleAt(
          now.subtract(const Duration(days: 7)),
          gasAmount: 4000,
        ), // 7 days ago: out of range
      ];
      final report = buildSalesReport(sales, range: ReportRange.week, now: now);
      expect(report.totalForRange, 3000);
    });

    test('month includes the last 30 days inclusive of today', () {
      final sales = [
        _saleAt(now, gasAmount: 1000),
        _saleAt(
          now.subtract(const Duration(days: 29)),
          gasAmount: 2000,
        ), // in range
        _saleAt(
          now.subtract(const Duration(days: 30)),
          gasAmount: 4000,
        ), // out of range
      ];
      final report = buildSalesReport(
        sales,
        range: ReportRange.month,
        now: now,
      );
      expect(report.totalForRange, 3000);
    });
  });

  group('breakdown by product type', () {
    test('sums gas into its own bucket, every product line into a shared "products" bucket', () {
      final sales = [
        _saleAt(now, gasAmount: 5000, cylinderLine: true, accessoryLine: true),
      ];
      final report = buildSalesReport(
        sales,
        range: ReportRange.today,
        now: now,
      );

      expect(report.breakdown.gas, 5000);
      expect(report.breakdown.products, 15300); // 15000 cylinder + 300 lighter
      expect(report.breakdown.grandTotal, 20300);
    });
  });

  group('last7Days', () {
    test('always has exactly 7 entries ending on now\'s day, regardless of selected range', () {
      final report = buildSalesReport([], range: ReportRange.today, now: now);
      expect(report.last7Days, hasLength(7));
      expect(report.last7Days.last.day, DateTime(2026, 9, 10));
      expect(report.last7Days.first.day, DateTime(2026, 9, 4));
    });

    test('buckets each sale into its own calendar day', () {
      final sales = [
        _saleAt(now, gasAmount: 1000),
        _saleAt(now.subtract(const Duration(days: 2)), gasAmount: 2000),
      ];
      final report = buildSalesReport(
        sales,
        range: ReportRange.month,
        now: now,
      );

      final todayBucket = report.last7Days.last;
      final twoDaysAgoBucket = report.last7Days[report.last7Days.length - 3];

      expect(todayBucket.total, 1000);
      expect(twoDaysAgoBucket.total, 2000);
    });
  });

  test('an empty sales list produces zero totals, not an error', () {
    final report = buildSalesReport([], range: ReportRange.month, now: now);
    expect(report.totalForRange, 0);
    expect(report.breakdown.grandTotal, 0);
  });
}
