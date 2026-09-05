import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/business/application/business_providers.dart';
import 'package:leumadepos/features/business/data/business_repository.dart';
import 'package:leumadepos/features/business/presentation/settings_screen.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';

/// Coverage for the Gas rate card specifically — see settings_screen_test.dart
/// for the capacity card, unaffected by this. Uses FakeAuthRepository's
/// seeded owner (chidi@leumadepos.test) since changeGasRate needs a
/// signed-in staff member to attribute the ledger entry to.
void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<(ProviderContainer, FakeInventoryRepository)> pumpSignedInScreen(WidgetTester tester) async {
    // Same phone-sized surface as settings_screen_test.dart's capacity
    // tests — the default 800x600 test surface puts the rate card's
    // "Save" button below the fold (two AppCards now, not one).
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final inventory = FakeInventoryRepository();
    final auth = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        businessRepositoryProvider.overrideWithValue(FakeBusinessRepository()),
        inventoryRepositoryProvider.overrideWithValue(inventory),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await settle(tester);

    // FakeAuthRepository.signInWithEmailAndPin has an internal
    // Future.delayed, which only resolves while something is pumping
    // frames — awaiting it directly here (before any pump) would
    // deadlock the test binding's fake clock forever. Unawaited + a
    // bounded settle() afterward is the established working pattern —
    // see verify_email_flow_test.dart.
    // ignore: unawaited_futures
    auth.signInWithEmailAndPin(email: 'chidi@leumadepos.test', pin: '1234');
    await settle(tester);

    // Nothing in SettingsScreen watches authStateProvider — only
    // GasRateController.confirmRateChange reads it, later, on demand.
    // A StreamProvider's FIRST read only starts its subscription; it
    // doesn't have a value synchronously on that same read. Warm it up
    // now (well before confirmRateChange ever runs) so its first value
    // has already arrived by then.
    container.read(authStateProvider);
    await settle(tester);

    return (container, inventory);
  }

  testWidgets('shows the current rate, and a confirmation preview showing the preserved kg before saving', (
    tester,
  ) async {
    final (_, inventory) = await pumpSignedInScreen(tester);

    expect(find.text('₦1,400/kg'), findsOneWidget); // FakeInventoryRepository's seeded rate

    await tester.ensureVisible(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, '1500');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await settle(tester);

    // 63000 units @ 1400/kg = 45kg — the confirmation must show that
    // exact preserved figure, not the new rate's units.
    expect(find.text('Change gas rate?'), findsOneWidget);
    expect(
      find.text(
        'Changing rate from ₦1,400 to ₦1,500/kg — your current 45 kg in stock will still read as 45 kg '
        'after this change.',
      ),
      findsOneWidget,
    );

    // Cancelling must not touch the repository at all.
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(inventory.gasRate.nairaPerKg, 1400);
  });

  testWidgets('confirming the dialog commits the rate change and preserves the physical kg', (tester) async {
    final (_, inventory) = await pumpSignedInScreen(tester);

    await tester.ensureVisible(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, '1500');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await settle(tester);

    await tester.tap(find.text('Change rate'));
    await settle(tester);

    expect(inventory.gasRate.nairaPerKg, 1500);
    // 45kg preserved: 45 * 1500 = 67500 (was 63000 @ 1400/kg).
    expect(inventory.currentGasStock.units, 67500);
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('rejects a zero/invalid rate without ever showing the confirmation dialog', (tester) async {
    final (_, inventory) = await pumpSignedInScreen(tester);

    await tester.ensureVisible(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, '0');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await settle(tester);

    expect(find.text('Change gas rate?'), findsNothing);
    expect(find.text('Enter a valid rate in ₦/kg.'), findsOneWidget);
    expect(inventory.gasRate.nairaPerKg, 1400);
  });
}
