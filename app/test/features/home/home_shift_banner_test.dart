import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/app.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/application/sales_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/data/sales_repository.dart';
import 'package:leumadepos/features/sell/domain/sale.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';

/// Home's shift banner specifically — see shift_gating_router_test.dart
/// for the closed-state ("day hasn't been opened yet") banner and the
/// actual /sell gating it corresponds to. This covers the open-state
/// banner: shows the correct expected-cash figure and links to Close Day.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('shows expected cash for an open shift and links to Close Day', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final shift = FakeShiftRepository(); // ₦10,000 float, no sales yet -> expected ₦10,000
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
          salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
          customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
          shiftRepositoryProvider.overrideWithValue(shift),
        ],
        child: const LeumadeposApp(),
      ),
    );
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'ifeoma@leumadepos.test');
    for (final digit in ['1', '1', '1', '1']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.tap(find.text('Sign in'));
    await settle(tester);

    expect(find.text('Day is open'), findsOneWidget);
    expect(find.text('₦10,000'), findsOneWidget);
    expect(find.text('The day hasn\'t been opened yet'), findsNothing);

    shift.debugApplySaleTotals(method: PaymentMethod.cash, amountNaira: 5000);
    await settle(tester);
    expect(find.text('₦15,000'), findsOneWidget); // expected cash updates live

    await tester.tap(find.text('Close day'));
    await settle(tester);

    expect(find.text('Count the drawer'), findsOneWidget); // reached Close Day
  });
}
