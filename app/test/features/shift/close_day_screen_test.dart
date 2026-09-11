import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/core/widgets/app_button.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';
import 'package:leumadepos/features/shift/presentation/close_day_screen.dart';
import 'package:leumadepos/features/sell/domain/sale.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(ProviderContainer, FakeShiftRepository)> pumpSignedInScreen(
    WidgetTester tester, {
    required VoidCallback onClosed,
  }) async {
    // The running-totals summary card pushes the submit button below the
    // fold on the default 800x600 test surface — same phone-sized fix as
    // settings_screen_gas_rate_test.dart.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // openShift: true (the default) seeds ₦10,000 float, no sales yet —
    // individual tests apply sales on top via debugApplySaleTotals.
    final shift = FakeShiftRepository();
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
        child: MaterialApp(home: CloseDayScreen(onClosed: onClosed)),
      ),
    );
    await settle(tester);

    // ignore: unawaited_futures
    auth.signInWithEmailAndPin(email: 'ifeoma@leumadepos.test', pin: '1111');
    await settle(tester);
    container.read(authStateProvider); // warm up the StreamProvider — see settings_screen_gas_rate_test.dart
    await settle(tester);

    return (container, shift);
  }

  testWidgets('shows the running totals and confirms with the correct variance before closing', (
    tester,
  ) async {
    var closed = false;
    final (_, shift) = await pumpSignedInScreen(tester, onClosed: () => closed = true);
    shift.debugApplySaleTotals(method: PaymentMethod.cash, amountNaira: 25000);
    await settle(tester);

    expect(find.text('₦10,000'), findsOneWidget); // opening float
    expect(find.text('₦25,000'), findsOneWidget); // cash sales

    await tester.enterText(find.byType(TextField), '34500'); // ₦500 short of the ₦35,000 expected
    await tester.pump(const Duration(milliseconds: 10));
    await tester.ensureVisible(find.byType(AppButton));
    await tester.tap(find.byType(AppButton));
    await settle(tester);

    expect(find.text('Close the day?'), findsOneWidget);
    expect(find.textContaining('₦500 short'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await settle(tester);

    expect(closed, isTrue);
    expect(shift.currentShift, isNull); // no longer open
  });

  testWidgets(
    'a cash expense shows in the summary and reduces expected cash — the confirmation dialog '
    'mentions it too',
    (tester) async {
      var closed = false;
      final (_, shift) = await pumpSignedInScreen(tester, onClosed: () => closed = true);
      shift.debugApplySaleTotals(method: PaymentMethod.cash, amountNaira: 25000);
      shift.debugApplyExpenseTotal(amountNaira: 4000);
      await settle(tester);

      expect(find.text('₦25,000'), findsOneWidget); // cash sales
      expect(find.text('₦4,000'), findsOneWidget); // cash expenses

      // Exact count against the reduced expected amount: 10000 + 25000 - 4000 = 31000.
      await tester.enterText(find.byType(TextField), '31000');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.ensureVisible(find.byType(AppButton));
      await tester.tap(find.byType(AppButton));
      await settle(tester);

      expect(find.text('Close the day?'), findsOneWidget);
      expect(find.textContaining('₦4,000 cash expenses'), findsOneWidget);
      expect(find.textContaining('Exact'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await settle(tester);

      expect(closed, isTrue);
    },
  );

  testWidgets(
    'no cash expenses this shift: the confirmation dialog omits the expenses clause entirely, unchanged '
    'from before this feature existed',
    (tester) async {
      final (_, shift) = await pumpSignedInScreen(tester, onClosed: () {});
      shift.debugApplySaleTotals(method: PaymentMethod.cash, amountNaira: 25000);
      await settle(tester);

      await tester.enterText(find.byType(TextField), '35000');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.ensureVisible(find.byType(AppButton));
      await tester.tap(find.byType(AppButton));
      await settle(tester);

      // Proves the conditional clause is omitted: if it had rendered, the
      // text right after "cash sales" would be " − ₦0 cash expenses)",
      // not directly ")" — checking for "cash expenses" alone would also
      // match this screen's own unrelated explanatory paragraph above the
      // summary card.
      expect(find.textContaining('₦25,000 cash sales)'), findsOneWidget);
    },
  );

  testWidgets('cancelling the confirmation leaves the shift open', (tester) async {
    var closed = false;
    final (_, shift) = await pumpSignedInScreen(tester, onClosed: () => closed = true);
    await settle(tester);

    await tester.enterText(find.byType(TextField), '10000');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.ensureVisible(find.byType(AppButton));
    await tester.tap(find.byType(AppButton));
    await settle(tester);

    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(closed, isFalse);
    expect(shift.currentShift, isNotNull);
  });

  testWidgets('an exact count shows as Exact, not a signed zero', (tester) async {
    final (_, shift) = await pumpSignedInScreen(tester, onClosed: () {});
    shift.debugApplySaleTotals(method: PaymentMethod.cash, amountNaira: 25000);
    await settle(tester);

    await tester.enterText(find.byType(TextField), '35000');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.ensureVisible(find.byType(AppButton));
    await tester.tap(find.byType(AppButton));
    await settle(tester);

    expect(find.textContaining('Exact'), findsOneWidget);
  });

  testWidgets('rejects an invalid counted amount without ever showing the confirmation dialog', (
    tester,
  ) async {
    final (_, shift) = await pumpSignedInScreen(tester, onClosed: () {});

    await tester.enterText(find.byType(TextField), '-1');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.ensureVisible(find.byType(AppButton));
    await tester.tap(find.byType(AppButton));
    await settle(tester);

    expect(find.text('Close the day?'), findsNothing);
    expect(find.text('Enter a valid counted amount in ₦.'), findsOneWidget);
    expect(shift.currentShift, isNotNull);
  });

  testWidgets(
    'at a 1440x900 desktop surface, the form still stays a sane width — not stretched edge-to-edge',
    (tester) async {
      await pumpSignedInScreen(tester, onClosed: () {});

      // pumpSignedInScreen pins a phone-sized surface for its own reason
      // (see that helper's comment) — override it here, after signing
      // in, for this test's own desktop-width case.
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await settle(tester);

      final box = tester.widget<ConstrainedBox>(
        find.byKey(const ValueKey('responsiveCenterConstraint')),
      );
      expect(box.constraints.maxWidth, 560);
    },
  );
}
