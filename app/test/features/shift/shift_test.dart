import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/shift/domain/shift.dart';

void main() {
  OpenShift shift({
    int openingFloatNaira = 10000,
    int cashTotalNaira = 0,
    int cardTotalNaira = 0,
    int transferTotalNaira = 0,
    int creditTotalNaira = 0,
    int salesCount = 0,
  }) {
    return OpenShift(
      openingFloatNaira: openingFloatNaira,
      openedByStaffId: 'staff-1',
      openedByStaffName: 'Ifeoma',
      openedAt: DateTime(2026, 9, 5, 8),
      cashTotalNaira: cashTotalNaira,
      cardTotalNaira: cardTotalNaira,
      transferTotalNaira: transferTotalNaira,
      creditTotalNaira: creditTotalNaira,
      salesCount: salesCount,
    );
  }

  group('OpenShift.expectedCashNaira — only cash sales feed the physical drawer', () {
    test('opening float alone, no sales yet', () {
      expect(shift(openingFloatNaira: 5000).expectedCashNaira, 5000);
    });

    test('cash sales add to the expected drawer amount', () {
      expect(shift(openingFloatNaira: 5000, cashTotalNaira: 32000).expectedCashNaira, 37000);
    });

    test('card/transfer/credit totals do NOT affect expected cash — money never entered this drawer', () {
      final s = shift(
        openingFloatNaira: 5000,
        cashTotalNaira: 10000,
        cardTotalNaira: 999999,
        transferTotalNaira: 999999,
        creditTotalNaira: 999999,
      );
      expect(s.expectedCashNaira, 15000);
    });
  });

  group('closeShift — variance against the counted drawer', () {
    test('exact count: zero variance', () {
      final result = closeShift(
        shift(openingFloatNaira: 10000, cashTotalNaira: 25000),
        countedCashNaira: 35000,
        staffId: 'staff-2',
        staffName: 'Chidi',
        closedAt: DateTime(2026, 9, 5, 20),
      );
      expect(result.expectedCashNaira, 35000);
      expect(result.varianceNaira, 0);
    });

    test('drawer short: negative variance', () {
      final result = closeShift(
        shift(openingFloatNaira: 10000, cashTotalNaira: 25000),
        countedCashNaira: 34500,
        staffId: 'staff-2',
        staffName: 'Chidi',
        closedAt: DateTime(2026, 9, 5, 20),
      );
      expect(result.varianceNaira, -500); // ₦500 short
    });

    test('drawer over: positive variance', () {
      final result = closeShift(
        shift(openingFloatNaira: 10000, cashTotalNaira: 25000),
        countedCashNaira: 35200,
        staffId: 'staff-2',
        staffName: 'Chidi',
        closedAt: DateTime(2026, 9, 5, 20),
      );
      expect(result.varianceNaira, 200); // ₦200 over
    });

    test('a shift with zero sales still reconciles against the bare opening float', () {
      final result = closeShift(
        shift(openingFloatNaira: 15000),
        countedCashNaira: 15000,
        staffId: 'staff-2',
        staffName: 'Chidi',
        closedAt: DateTime(2026, 9, 5, 20),
      );
      expect(result.varianceNaira, 0);
    });

    test('carries every running total through into the closed record, untouched', () {
      final result = closeShift(
        shift(
          openingFloatNaira: 10000,
          cashTotalNaira: 25000,
          cardTotalNaira: 8000,
          transferTotalNaira: 12000,
          creditTotalNaira: 4000,
          salesCount: 9,
        ),
        countedCashNaira: 35000,
        staffId: 'staff-2',
        staffName: 'Chidi',
        closedAt: DateTime(2026, 9, 5, 20),
      );
      expect(result.cardTotalNaira, 8000);
      expect(result.transferTotalNaira, 12000);
      expect(result.creditTotalNaira, 4000);
      expect(result.salesCount, 9);
      expect(result.openedByStaffId, 'staff-1');
      expect(result.closedByStaffId, 'staff-2');
    });
  });
}
