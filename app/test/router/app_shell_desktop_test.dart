import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/app.dart';
import 'package:leumadepos/core/widgets/app_bottom_nav.dart';
import 'package:leumadepos/core/widgets/app_side_rail.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/application/sales_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/data/sales_repository.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';

/// Proves AppShell actually swaps to AppSideRail at desktop widths — same
/// real navigation (StatefulNavigationShell, the real router) as
/// shift_gating_router_test.dart, just at a desktop-sized surface instead
/// of the default test size.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void useDesktopSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget appWithFakes() {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        inventoryRepositoryProvider.overrideWithValue(
          FakeInventoryRepository(),
        ),
        salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
        customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
        shiftRepositoryProvider.overrideWithValue(FakeShiftRepository()),
      ],
      child: const LeumadeposApp(),
    );
  }

  Future<void> signIn(
    WidgetTester tester, {
    required String email,
    required String pin,
  }) async {
    await tester.enterText(find.byType(TextField), email);
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.tap(find.text('Sign in'));
    await settle(tester);
  }

  testWidgets(
    'at a 1440x900 surface, signed in as owner, the rail shows and the bottom tab bar does not',
    (tester) async {
      useDesktopSurface(tester);
      await tester.pumpWidget(appWithFakes());
      await settle(tester);
      await signIn(tester, email: 'chidi@leumadepos.test', pin: '1234');

      expect(find.byType(AppSideRail), findsOneWidget);
      expect(find.byType(AppBottomNav), findsNothing);
    },
  );

  testWidgets(
    'at a 1440x900 surface, tapping a rail item navigates to that branch',
    (tester) async {
      useDesktopSurface(tester);
      await tester.pumpWidget(appWithFakes());
      await settle(tester);
      await signIn(tester, email: 'chidi@leumadepos.test', pin: '1234');

      await tester.tap(
        find.descendant(
          of: find.byType(AppSideRail),
          matching: find.text('Sell'),
        ),
      );
      await settle(tester);

      // The real Sell screen's own content, not just a route change.
      expect(find.text('Cart'), findsOneWidget);
    },
  );

  testWidgets(
    'at a 1440x900 surface, signed in as attendant, Stock and Reports are absent from the rail',
    (tester) async {
      useDesktopSurface(tester);
      await tester.pumpWidget(appWithFakes());
      await settle(tester);
      await signIn(tester, email: 'ifeoma@leumadepos.test', pin: '1111');

      expect(find.byType(AppSideRail), findsOneWidget);
      final rail = find.byType(AppSideRail);
      expect(
        find.descendant(of: rail, matching: find.text('Stock')),
        findsNothing,
      );
      expect(
        find.descendant(of: rail, matching: find.text('Reports')),
        findsNothing,
      );
      // Still sees the tabs every role gets.
      expect(
        find.descendant(of: rail, matching: find.text('Home')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rail, matching: find.text('Sell')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rail, matching: find.text('Customers')),
        findsOneWidget,
      );
    },
  );
}
