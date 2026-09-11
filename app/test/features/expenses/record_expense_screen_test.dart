import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/core/widgets/app_button.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/expenses/application/expense_providers.dart';
import 'package:leumadepos/features/expenses/data/expense_repository.dart';
import 'package:leumadepos/features/expenses/presentation/record_expense_screen.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> typeAmount(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tapVisible(tester, find.text(digit).first);
    }
    await settle(tester);
  }

  Future<(ProviderContainer, FakeShiftRepository, FakeExpenseRepository)> pumpSignedInScreen(
    WidgetTester tester, {
    required VoidCallback onRecorded,
    bool openShift = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final shift = FakeShiftRepository(openShift: openShift);
    final expenses = FakeExpenseRepository(shift: shift);
    final auth = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        shiftRepositoryProvider.overrideWithValue(shift),
        expenseRepositoryProvider.overrideWithValue(expenses),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: RecordExpenseScreen(onRecorded: onRecorded)),
      ),
    );
    await settle(tester);

    // ignore: unawaited_futures
    auth.signInWithEmailAndPin(email: 'ifeoma@leumadepos.test', pin: '1111');
    await settle(tester);
    container.read(authStateProvider); // warm up the StreamProvider — see close_day_screen_test.dart
    await settle(tester);

    return (container, shift, expenses);
  }

  testWidgets('a cash expense against an open shift records and calls onRecorded', (tester) async {
    var recorded = false;
    final (_, shift, expenses) = await pumpSignedInScreen(tester, onRecorded: () => recorded = true);

    await tapVisible(tester, find.text('Cash'));
    await typeAmount(tester, '4000');
    await tapVisible(tester, find.text('Fuel'));

    await tester.ensureVisible(find.byType(AppButton));
    await tapVisible(tester, find.byType(AppButton));
    await settle(tester);

    expect(recorded, isTrue);
    expect(expenses.debugExpenses, hasLength(1));
    expect(expenses.debugExpenses.single.amountNaira, 4000);
    expect(shift.currentShift!.expenseTotalNaira, 4000);
  });

  testWidgets('a transfer expense needs no shift open at all', (tester) async {
    var recorded = false;
    final (_, shift, expenses) = await pumpSignedInScreen(
      tester,
      onRecorded: () => recorded = true,
      openShift: false,
    );

    await tapVisible(tester, find.text('Transfer'));
    await typeAmount(tester, '7000');
    await tapVisible(tester, find.text('Supplies'));

    await tester.ensureVisible(find.byType(AppButton));
    await tapVisible(tester, find.byType(AppButton));
    await settle(tester);

    expect(recorded, isTrue);
    expect(expenses.debugExpenses, hasLength(1));
    expect(shift.currentShift, isNull); // untouched — still no shift
  });

  testWidgets('a cash expense with no shift open shows an error and does not record', (tester) async {
    var recorded = false;
    final (_, _, expenses) = await pumpSignedInScreen(
      tester,
      onRecorded: () => recorded = true,
      openShift: false,
    );

    await tapVisible(tester, find.text('Cash'));
    await typeAmount(tester, '4000');
    await tapVisible(tester, find.text('Fuel'));

    await tester.ensureVisible(find.byType(AppButton));
    await tapVisible(tester, find.byType(AppButton));
    await settle(tester);

    expect(recorded, isFalse);
    expect(expenses.debugExpenses, isEmpty);
    expect(find.textContaining('No shift is currently open'), findsOneWidget);
  });

  testWidgets('category "Other" reveals a note field, required before submit is enabled', (tester) async {
    await pumpSignedInScreen(tester, onRecorded: () {});

    await tapVisible(tester, find.text('Transfer'));
    await typeAmount(tester, '3000');

    // Note field isn't shown at all until "Other" is selected.
    expect(find.text('What was it?'), findsNothing);

    await tapVisible(tester, find.text('Other').last); // category chip, not the payment-method tile
    await settle(tester);

    expect(find.text('What was it?'), findsOneWidget);
    final submitButton = tester.widget<AppButton>(find.byType(AppButton));
    expect(submitButton.onPressed, isNull); // no note yet

    await tester.enterText(find.byType(TextField), 'Signboard repair');
    await settle(tester);

    final submitButtonAfterNote = tester.widget<AppButton>(find.byType(AppButton));
    expect(submitButtonAfterNote.onPressed, isNotNull);
  });

  testWidgets('submit stays disabled until amount, method, and category are all set', (tester) async {
    await pumpSignedInScreen(tester, onRecorded: () {});

    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);

    await tapVisible(tester, find.text('Cash'));
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull); // no amount/category yet

    await typeAmount(tester, '1500');
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull); // no category yet

    await tapVisible(tester, find.text('Maintenance'));
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
  });
}
