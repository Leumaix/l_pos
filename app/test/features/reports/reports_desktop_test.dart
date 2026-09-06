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
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';

/// Desktop-only coverage for the multi-panel dashboard arrangement — the
/// narrow/tablet single column is untouched and stays covered by
/// reports_shift_history_test.dart (which runs at the default, narrow
/// test surface).
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('at a 1440x900 surface, the stat tiles and every panel render — a real dashboard, '
      'not just a wider single column', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await settle(tester);

    // Top row: the four small stat tiles.
    expect(find.text("Today's sales"), findsOneWidget);
    expect(find.text('Gas remaining'), findsOneWidget);
    expect(find.text('Low-stock items'), findsOneWidget);
    expect(find.text('Debtors outstanding'), findsOneWidget);

    // Below: the bigger panels, still all present, just rearranged.
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.text('By product type'), findsOneWidget);
    expect(find.text('Shift history'), findsOneWidget);
    expect(find.text('No shifts closed yet.'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('switching the date range still updates the desktop dashboard\'s sales stat tile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await settle(tester);

    expect(find.text("Today's sales"), findsOneWidget);

    await tester.tap(find.text('Week'));
    await settle(tester);

    expect(find.text("This week's sales"), findsOneWidget);
    expect(find.text("Today's sales"), findsNothing);
  });
}
