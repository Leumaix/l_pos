import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/gifts/domain/gift.dart';
import 'package:leumadepos/features/gifts/domain/gifts_report.dart';
import 'package:leumadepos/features/reports/domain/sales_report.dart';

Gift _giftAt(DateTime when, {int estimatedValueNaira = 1400}) {
  return Gift(
    id: 'gift-${when.millisecondsSinceEpoch}',
    itemType: GiftItemType.gas,
    quantity: 1,
    estimatedValueNaira: estimatedValueNaira,
    reason: 'Sample',
    staffId: 's1',
    staffName: 'Staff',
    shiftId: 'hist-1',
    requiresApproval: false,
    createdAt: when,
  );
}

void main() {
  final now = DateTime(2026, 9, 15, 14, 0);

  test('totalForRange sums only gifts within the range — today', () {
    final gifts = [
      _giftAt(now, estimatedValueNaira: 2000), // today
      _giftAt(now.subtract(const Duration(days: 1)), estimatedValueNaira: 5000), // yesterday, excluded
    ];
    final report = buildGiftsReport(gifts, range: ReportRange.today, now: now);
    expect(report.totalForRange, 2000);
  });

  test('week range includes the last 7 days, inclusive of today', () {
    final gifts = [
      _giftAt(now, estimatedValueNaira: 1000),
      _giftAt(now.subtract(const Duration(days: 6)), estimatedValueNaira: 500),
      _giftAt(now.subtract(const Duration(days: 7)), estimatedValueNaira: 999999), // just outside, excluded
    ];
    final report = buildGiftsReport(gifts, range: ReportRange.week, now: now);
    expect(report.totalForRange, 1500);
  });

  test('an empty list reports a zero total, not an error', () {
    final report = buildGiftsReport(const [], range: ReportRange.today, now: now);
    expect(report.totalForRange, 0);
  });

  test('both gas and product gifts count toward the total', () {
    final gifts = [
      _giftAt(now, estimatedValueNaira: 1400), // gas
      Gift(
        id: 'gift-product',
        itemType: GiftItemType.product,
        productId: 'acc-hose',
        quantity: 2,
        estimatedValueNaira: 1600,
        reason: 'Damaged',
        staffId: 's1',
        staffName: 'Staff',
        shiftId: 'hist-1',
        requiresApproval: false,
        createdAt: now,
      ),
    ];
    final report = buildGiftsReport(gifts, range: ReportRange.today, now: now);
    expect(report.totalForRange, 3000);
  });
}
