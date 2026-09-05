import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/business/application/business_providers.dart';
import 'package:leumadepos/features/business/data/business_repository.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/reports/presentation/reports_screen.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/application/sales_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/data/sales_repository.dart';
import 'package:leumadepos/features/sell/domain/sale.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';

/// Reports' owner-only "Shift history" section — see
/// shift_rules.test.mjs for the matching owner-only read rule on
/// shiftHistory. The existing date-range sales view (Today/Week/Month) is
/// untouched by this — additive, not a reorganization.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget pumpableReports(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ReportsScreen()),
    );
  }

  testWidgets('shows "no shifts closed yet" when history is empty', (tester) async {
    final container = ProviderContainer(
      overrides: [
        salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
        customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
        inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
        businessRepositoryProvider.overrideWithValue(FakeBusinessRepository()),
        shiftRepositoryProvider.overrideWithValue(FakeShiftRepository(openShift: false)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpableReports(container));
    await settle(tester);

    expect(find.text('Shift history'), findsOneWidget);
    expect(find.text('No shifts closed yet.'), findsOneWidget);
  });

  testWidgets('lists a closed shift with its totals and a flagged variance', (tester) async {
    final shift = FakeShiftRepository(openShift: false);
    await shift.openDay(openingFloatNaira: 10000, staffId: 'staff-1', staffName: 'Ifeoma');
    shift.debugApplySaleTotals(method: PaymentMethod.cash, amountNaira: 25000);
    await shift.closeDay(countedCashNaira: 34500, staffId: 'staff-2', staffName: 'Chidi (Owner)');

    final container = ProviderContainer(
      overrides: [
        salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
        customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
        inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
        businessRepositoryProvider.overrideWithValue(FakeBusinessRepository()),
        shiftRepositoryProvider.overrideWithValue(shift),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(pumpableReports(container));
    await settle(tester);

    expect(find.text('No shifts closed yet.'), findsNothing);
    expect(find.textContaining('Opened by Ifeoma'), findsOneWidget);
    expect(find.textContaining('Closed by Chidi (Owner)'), findsOneWidget);
    expect(find.textContaining('₦500 short'), findsOneWidget); // 34500 - (10000 + 25000)
  });
}
