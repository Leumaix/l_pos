import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/stock/presentation/restock_screen.dart';

void main() {
  // RestockController.commitRestock now requires a signed-in staff member
  // (attributing the gasStockLedger entry a real restock writes) — sign
  // one in directly through the repository rather than via the login UI,
  // since these tests are exercising RestockScreen in isolation.
  //
  // Deliberately NOT awaited here: FakeAuthRepository.signInWithEmailAndPin
  // has an internal Future.delayed(500ms), and directly awaiting an app
  // async call with an internal delay outside tester.pump() deadlocks
  // under AutomatedTestWidgetsFlutterBinding's fake clock. Firing it off
  // and letting the caller's own pumpWidget/pumpAndSettle advance the
  // clock resolves it well before any test taps "Confirm restock".
  ProviderContainer signedInContainer() {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      ],
    );
    unawaited(
      container.read(authRepositoryProvider).signInWithEmailAndPin(
        email: 'chidi@leumadepos.test',
        pin: '1234',
      ),
    );
    // RestockScreen never itself watches authStateProvider, so nothing
    // would otherwise subscribe to it until commitRestock's own
    // ref.read() — too late for that read to see settled AsyncData
    // rather than the initial AsyncLoading. Force early subscription so
    // it has already resolved by the time a test taps "Confirm restock".
    container.listen(authStateProvider, (previous, next) {});
    return container;
  }

  testWidgets(
    'restocking through the actual UI adds to a nonzero starting balance — '
    'regression for an overwrite bug that a zero-plus-delivery test would '
    'hide, since it would only show up once real stock exists',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = signedInContainer();
      addTearDown(container.dispose);

      // The default FakeInventoryRepository starts at 63000 units
      // (45kg at ₦1,400/kg) — a nonzero starting balance, deliberately,
      // not a fresh/zero one.
      final inventory = container.read(inventoryRepositoryProvider);
      expect(
        inventory.currentGasStock.units,
        63000,
        reason: 'sanity check on the fake seed',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RestockScreen()),
        ),
      );
      // pumpAndSettle only keeps advancing the fake clock while a frame
      // is scheduled — signing in doesn't itself trigger a rebuild here,
      // so it can stop before the sign-in's internal 500ms delay
      // resolves. Force the clock past it explicitly first.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Deliver 10kg -> 10 * 1400 = 14000 units.
      await tester.tap(find.text('1').first);
      await tester.pump();
      await tester.tap(find.text('0').first);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('New total'), findsOneWidget);
      expect(
        find.text('55 kg'),
        findsOneWidget,
      ); // 45kg + 10kg, shown live before confirming

      await tester.ensureVisible(find.text('Confirm restock'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm restock'));
      await tester.pumpAndSettle();

      // The whole point: old balance (63000) + this delivery (14000),
      // not just the delivery on its own.
      expect(inventory.currentGasStock.units, 77000);
      expect(inventory.currentGasStock.units, isNot(14000));
    },
  );

  testWidgets(
    'a second restock keeps adding on top, not replacing the running total',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = signedInContainer();
      addTearDown(container.dispose);
      final inventory = container.read(inventoryRepositoryProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: RestockScreen()),
        ),
      );
      // pumpAndSettle only keeps advancing the fake clock while a frame
      // is scheduled — signing in doesn't itself trigger a rebuild here,
      // so it can stop before the sign-in's internal 500ms delay
      // resolves. Force the clock past it explicitly first.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      Future<void> deliver(String digit) async {
        await tester.tap(find.text(digit).first);
        await tester.pump();
        await tester.ensureVisible(find.text('Confirm restock'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm restock'));
        await tester.pumpAndSettle();
      }

      await deliver('5'); // +5kg -> 63000 + 7000 = 70000
      expect(inventory.currentGasStock.units, 70000);

      await deliver(
        '5',
      ); // +5kg again -> 70000 + 7000 = 77000, not a reset to 7000
      expect(inventory.currentGasStock.units, 77000);
    },
  );
}
