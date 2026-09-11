import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/core/widgets/app_button.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/gifts/application/gift_providers.dart';
import 'package:leumadepos/features/gifts/data/gift_repository.dart';
import 'package:leumadepos/features/gifts/presentation/record_gift_screen.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/shift/application/shift_providers.dart';
import 'package:leumadepos/features/shift/data/shift_repository.dart';

/// Widget coverage for the owner-PIN-approval mechanism specifically —
/// the domain/controller layer already covers the underlying logic
/// exhaustively (gift_controller_test.dart); this file proves the SCREEN
/// wires it correctly: the approval section stays hidden for an
/// under-threshold gift, appears for an over-threshold one, a wrong PIN
/// is rejected without committing, and a correct PIN commits — all while
/// the active session visibly stays the ATTENDANT's throughout, never
/// switching to the owner who just typed their PIN. That last point is
/// the entire reason this mechanism exists (see AuthRepository.
/// verifyActiveOwnerPin's own doc comment) — proven here at the screen
/// level, not just the controller level, before the live-device pass.
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

  // Quantity is entered BEFORE the owner-approval section can ever
  // appear (it only shows once quantity crosses the threshold), so at
  // this point there's exactly one NumericKeypad on screen — `.first`
  // is unambiguous.
  Future<void> typeQuantity(WidgetTester tester, String chars) async {
    for (final char in chars.split('')) {
      await tapVisible(tester, find.text(char).first);
    }
    await settle(tester);
  }

  // Once the approval section is visible there are TWO NumericKeypads on
  // screen (quantity's and the PIN's) — the PIN keypad is the one added
  // later in the tree, so `.last` targets it, not the quantity keypad
  // above it.
  Future<void> typeOwnerPin(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tapVisible(tester, find.text(digit).last);
    }
    await settle(tester);
  }

  Future<(ProviderContainer, FakeGiftRepository)> pumpSignedInScreen(
    WidgetTester tester, {
    required VoidCallback onRecorded,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final shift = FakeShiftRepository(openShift: true);
    final inventory = FakeInventoryRepository();
    final gifts = FakeGiftRepository(inventory: inventory, shift: shift);
    final auth = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        shiftRepositoryProvider.overrideWithValue(shift),
        inventoryRepositoryProvider.overrideWithValue(inventory),
        giftRepositoryProvider.overrideWithValue(gifts),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: RecordGiftScreen(onRecorded: onRecorded)),
      ),
    );
    await settle(tester);

    // ignore: unawaited_futures
    auth.signInWithEmailAndPin(email: 'ifeoma@leumadepos.test', pin: '1111'); // FakeAuthRepository's seeded attendant
    await settle(tester);
    container.read(authStateProvider); // warm up the StreamProvider — see record_expense_screen_test.dart
    await settle(tester);

    return (container, gifts);
  }

  testWidgets(
    'a gas gift at or under the 2kg threshold commits without the owner-approval section ever appearing',
    (tester) async {
      var recorded = false;
      final (_, gifts) = await pumpSignedInScreen(tester, onRecorded: () => recorded = true);

      await typeQuantity(tester, '1.5'); // under the 2kg threshold
      await tester.enterText(find.byType(TextField).first, 'Sample for a regular customer');
      await settle(tester);

      expect(find.text("This gift needs the owner's approval"), findsNothing);

      await tapVisible(tester, find.byType(AppButton));
      await settle(tester);

      expect(recorded, isTrue);
      expect(gifts.debugGifts, hasLength(1));
      expect(gifts.debugGifts.single.requiresApproval, isFalse);
    },
  );

  testWidgets('an over-threshold gift reveals the approval section; a wrong owner PIN shows an error '
      'and commits nothing', (tester) async {
    var recorded = false;
    final (_, gifts) = await pumpSignedInScreen(tester, onRecorded: () => recorded = true);

    await typeQuantity(tester, '3'); // over the 2kg threshold
    await tester.enterText(find.byType(TextField).first, 'Large sample');
    await settle(tester);

    expect(find.text("This gift needs the owner's approval"), findsOneWidget);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull); // no owner email/PIN yet

    await tester.enterText(find.byType(TextField).last, 'chidi@leumadepos.test'); // FakeAuthRepository's seeded owner
    await typeOwnerPin(tester, '0000'); // wrong PIN
    await settle(tester);

    await tapVisible(tester, find.byType(AppButton));
    await settle(tester);

    expect(recorded, isFalse);
    expect(gifts.debugGifts, isEmpty);
    expect(find.textContaining('Incorrect owner email or PIN'), findsOneWidget);
  });

  testWidgets(
    'an over-threshold gift commits once the correct owner PIN is entered, and the active session '
    'stays the ATTENDANT\'s throughout — never switches to the owner who just typed their PIN',
    (tester) async {
      var recorded = false;
      final (container, gifts) = await pumpSignedInScreen(tester, onRecorded: () => recorded = true);

      await typeQuantity(tester, '3'); // over the 2kg threshold
      await tester.enterText(find.byType(TextField).first, 'Large sample');
      await settle(tester);

      await tester.enterText(find.byType(TextField).last, 'chidi@leumadepos.test');
      await typeOwnerPin(tester, '1234'); // FakeAuthRepository's seeded owner's correct PIN
      await settle(tester);

      await tapVisible(tester, find.byType(AppButton));
      await settle(tester);

      expect(recorded, isTrue);
      expect(gifts.debugGifts, hasLength(1));
      expect(gifts.debugGifts.single.requiresApproval, isTrue);
      expect(gifts.debugGifts.single.approvedByOwnerUid, 'seed-owner');

      // The whole point of the mechanism (see AuthRepository.
      // verifyActiveOwnerPin's own doc comment): the owner typing their
      // PIN to approve must never activate their own session on this
      // device. The signed-in user stays the attendant.
      expect(container.read(authStateProvider).value?.email, 'ifeoma@leumadepos.test');
    },
  );
}
