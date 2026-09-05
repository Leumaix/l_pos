import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leumadepos/app.dart';
import 'package:leumadepos/core/widgets/pin_dots.dart';
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

Widget _appWithFakeAuth() {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      // Gas stock, sales, and shift state all moved to real Firestore —
      // without these overrides, Home's dashboard (gas-remaining, and
      // today's-sales for an owner) and the router's shift-open check
      // would hit the real (signed-out-in-tests) Firestore path and
      // throw.
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
      customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
      shiftRepositoryProvider.overrideWithValue(FakeShiftRepository()),
    ],
    child: const LeumadeposApp(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The default 800x600 test surface is shorter than this phone-first
  // layout (logo + fields + full keypad + button); use a real phone size
  // so every widget is actually on screen and tappable.
  Future<void> useDefaultPhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'sign-in flow: PIN keypad fills dots and unlocks the sign-in button, '
    'then correct credentials land on Home',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      await tester.pumpWidget(_appWithFakeAuth());
      await tester.pumpAndSettle();

      expect(find.text('Sign in to start selling'), findsOneWidget);

      // Starts with no PIN entered yet.
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);

      await tester.enterText(find.byType(TextField), 'chidi@leumadepos.test');
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 4);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Chidi (Owner)'), findsOneWidget);
      expect(find.text('Quick actions'), findsOneWidget);
    },
  );

  testWidgets('wrong PIN shows an error and clears the PIN entry', (
    tester,
  ) async {
    await useDefaultPhoneSurface(tester);
    await tester.pumpWidget(_appWithFakeAuth());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'chidi@leumadepos.test');
    for (final digit in ['9', '9', '9', '9']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect email or PIN'), findsOneWidget);
    expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);
  });
}
