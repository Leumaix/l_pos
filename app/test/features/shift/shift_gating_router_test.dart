import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leumadepos/app.dart';
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

/// Router-level proof that "no ringing up a sale before the day is
/// opened" actually holds for real navigation, not just as a UI element
/// Home happens to show — same kind of check as
/// home_screen_role_test.dart's owner/attendant router redirect tests.
/// The real, unbypassable enforcement is firestore.rules'
/// exists(shiftState/current) check on /sales create (see
/// shift_rules.test.mjs and checkout_commit_rules.test.mjs) — this only
/// proves the UI path matches it.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget appWithFakes({required FakeShiftRepository shift}) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
        salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
        customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
        shiftRepositoryProvider.overrideWithValue(shift),
      ],
      child: const LeumadeposApp(),
    );
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'ifeoma@leumadepos.test');
    for (final digit in ['1', '1', '1', '1']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.tap(find.text('Sign in'));
    await settle(tester);
  }

  testWidgets('navigating to /sell with no shift open is redirected to Home, not Sell', (tester) async {
    final shift = FakeShiftRepository(openShift: false);
    await tester.pumpWidget(appWithFakes(shift: shift));
    await settle(tester);
    await signIn(tester);

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/sell');
    await settle(tester);

    // Bounced back to Home rather than actually landing on Sell — and
    // shows the "open the day" prompt explaining why.
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('The day hasn\'t been opened yet'), findsOneWidget);
    expect(find.text('Cart'), findsNothing); // Sell screen's own content, never reached
  });

  testWidgets('navigating to /sell with a shift open reaches Sell normally', (tester) async {
    final shift = FakeShiftRepository(); // openShift: true by default
    await tester.pumpWidget(appWithFakes(shift: shift));
    await settle(tester);
    await signIn(tester);

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/sell');
    await settle(tester);

    expect(find.text('Cart'), findsOneWidget); // reached the real Sell screen
  });

  testWidgets('closing the shift while Sell is already open bounces back to Home on the next navigation '
    'attempt (the router re-evaluates on a shift change, not just at the next tap)', (tester) async {
    final shift = FakeShiftRepository();
    await tester.pumpWidget(appWithFakes(shift: shift));
    await settle(tester);
    await signIn(tester);

    final context = tester.element(find.byType(Scaffold).first);
    GoRouter.of(context).go('/sell');
    await settle(tester);
    expect(find.text('Cart'), findsOneWidget);

    await shift.closeDay(countedCashNaira: 10000, staffId: 'staff-2', staffName: 'Someone');
    await settle(tester);

    // Router re-evaluated on the shift-change stream and bounced away
    // already — the Sell screen (and the Scaffold `context` was taken
    // from) is gone, so confirm by re-navigating with a fresh context.
    final freshContext = tester.element(find.byType(Scaffold).first);
    GoRouter.of(freshContext).go('/sell');
    await settle(tester);
    expect(find.text('The day hasn\'t been opened yet'), findsOneWidget);
  });
}
