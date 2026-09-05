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

/// Proves the owner/attendant split actually holds end to end — not just
/// that Home leaves a tile off, but that an attendant is genuinely
/// blocked from Stock/Reports at the router level too (see
/// app_router.dart's redirect and app_shell.dart's tab filtering).
void main() {
  Future<void> useDefaultPhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> signIn(WidgetTester tester, {required String email, required List<String> pinDigits}) async {
    await tester.enterText(find.byType(TextField), email);
    for (final digit in pinDigits) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
  }

  Widget appWithFakeAuth() {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
        salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
        customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
        shiftRepositoryProvider.overrideWithValue(FakeShiftRepository()),
      ],
      child: const LeumadeposApp(),
    );
  }

  testWidgets(
    'attendant sees no revenue/debt figures and no Stock/Reports tiles or tabs',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      await tester.pumpWidget(appWithFakeAuth());
      await tester.pumpAndSettle();

      await signIn(tester, email: 'ifeoma@leumadepos.test', pinDigits: ['1', '1', '1', '1']);

      expect(find.text('Ifeoma'), findsOneWidget);
      // Explicit regression check: /sales reads are owner-only at the
      // rules level, so an attendant's dashboardSummaryProvider must
      // never subscribe to salesProvider at all — if it did, this would
      // render the error state instead of the dashboard.
      expect(find.text('Could not load dashboard'), findsNothing);
      expect(find.text("Today's sales"), findsNothing);
      expect(find.text('Amount owed'), findsNothing);
      // Still sees what the job actually needs.
      expect(find.text('Gas remaining'), findsOneWidget);

      expect(find.text('Sell'), findsWidgets); // quick action + bottom tab
      expect(find.text('Customers'), findsWidgets);
      expect(find.text('Stock'), findsNothing);
      expect(find.text('Reports'), findsNothing);
    },
  );

  testWidgets(
    'owner still sees full dashboard and Stock/Reports tiles and tabs',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      await tester.pumpWidget(appWithFakeAuth());
      await tester.pumpAndSettle();

      await signIn(tester, email: 'chidi@leumadepos.test', pinDigits: ['1', '2', '3', '4']);

      expect(find.text('Chidi (Owner)'), findsOneWidget);
      expect(find.text("Today's sales"), findsOneWidget);
      expect(find.text('Amount owed'), findsOneWidget);
      expect(find.text('Stock'), findsWidgets);
      expect(find.text('Reports'), findsWidgets);
    },
  );

  testWidgets(
    'attendant navigating directly to /stock is redirected to Home by the router, not just missing a tile',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      await tester.pumpWidget(appWithFakeAuth());
      await tester.pumpAndSettle();

      await signIn(tester, email: 'ifeoma@leumadepos.test', pinDigits: ['1', '1', '1', '1']);

      final context = tester.element(find.byType(Scaffold).first);
      GoRouter.of(context).go('/stock');
      await tester.pumpAndSettle();

      // Bounced back to Home rather than actually landing on Stock.
      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.text('Gas remaining'), findsOneWidget);
      expect(find.text('Restock'), findsNothing); // Stock screen's own content, never reached
    },
  );

  testWidgets(
    'tapping the account icon opens the menu immediately, even when a redundant '
    'auth-state emission (e.g. a token refresh) lands mid-tap',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      final authRepository = FakeAuthRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(authRepository),
            inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
            salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
            customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
            shiftRepositoryProvider.overrideWithValue(FakeShiftRepository()),
          ],
          child: const LeumadeposApp(),
        ),
      );
      await tester.pumpAndSettle();
      await signIn(tester, email: 'chidi@leumadepos.test', pinDigits: ['1', '2', '3', '4']);

      // Simulates a redundant, same-role authStateChanges emission
      // (AppUser has no == override, so a token refresh producing a new
      // instance with identical fields still counts as "different" to
      // anything watching the raw provider) landing between pointer-down
      // and pointer-up on the account icon — the kind of interleaving
      // implicated in a real device bug where the menu silently failed
      // to open. Honesty check: reverting both the app_shell.dart .select
      // fix and app_bottom_nav.dart's ValueKey fix does NOT make this
      // test fail — Flutter's synchronous test-binding gesture handling
      // doesn't reproduce whatever real hardware-timing race actually
      // triggered the bug on-device. This test is still worth keeping
      // (a real, valid interleaving that should never break the menu),
      // but it is not proof the underlying race is fixed — that was
      // confirmed separately, live, on the actual device (5 clean
      // single-tap repro attempts with no misfire, versus the bug
      // reproducing on an earlier attempt before the fix).
      final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.account_circle_outlined)));
      authRepository.debugReemitCurrentUser();
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(find.text('Signed in as'), findsOneWidget);
      expect(find.text('Invite staff'), findsOneWidget);
    },
  );
}
