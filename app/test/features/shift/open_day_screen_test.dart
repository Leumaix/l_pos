import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/core/widgets/app_button.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';
import 'package:leumadepos/features/shift/presentation/open_day_screen.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(ProviderContainer, FakeShiftRepository)> pumpSignedInScreen(
    WidgetTester tester, {
    required VoidCallback onOpened,
  }) async {
    final shift = FakeShiftRepository(openShift: false);
    final auth = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        shiftRepositoryProvider.overrideWithValue(shift),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: OpenDayScreen(onOpened: onOpened)),
      ),
    );
    await settle(tester);

    // ignore: unawaited_futures
    auth.signInWithEmailAndPin(email: 'chidi@leumadepos.test', pin: '1234');
    await settle(tester);
    container.read(authStateProvider); // warm up the StreamProvider — see settings_screen_gas_rate_test.dart
    await settle(tester);

    return (container, shift);
  }

  testWidgets('opens the day with the entered float and reports back via onOpened', (tester) async {
    var opened = false;
    final (_, shift) = await pumpSignedInScreen(tester, onOpened: () => opened = true);

    await tester.enterText(find.byType(TextField), '15000');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byType(AppButton));
    await settle(tester);

    expect(opened, isTrue);
    expect(shift.currentShift, isNotNull);
    expect(shift.currentShift!.openingFloatNaira, 15000);
    expect(shift.currentShift!.openedByStaffName, 'Chidi (Owner)');
  });

  testWidgets('allows a zero float — a legitimate starting point, unlike gas rate/tank capacity', (
    tester,
  ) async {
    var opened = false;
    final (_, shift) = await pumpSignedInScreen(tester, onOpened: () => opened = true);

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byType(AppButton));
    await settle(tester);

    expect(opened, isTrue);
    expect(shift.currentShift!.openingFloatNaira, 0);
  });

  testWidgets('rejects a negative float without opening anything', (tester) async {
    var opened = false;
    final (_, shift) = await pumpSignedInScreen(tester, onOpened: () => opened = true);

    await tester.enterText(find.byType(TextField), '-500');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byType(AppButton));
    await settle(tester);

    expect(opened, isFalse);
    expect(shift.currentShift, isNull);
    expect(find.text('Enter a valid starting float in ₦.'), findsOneWidget);
  });
}
