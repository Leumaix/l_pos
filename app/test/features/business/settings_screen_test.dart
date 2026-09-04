import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/business/application/business_providers.dart';
import 'package:leumadepos/features/business/data/business_repository.dart';
import 'package:leumadepos/features/business/presentation/settings_screen.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'shows the current capacity and saves a new one to the repository',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final business = FakeBusinessRepository(initialCapacityKg: 250);
      final container = ProviderContainer(
        overrides: [businessRepositoryProvider.overrideWithValue(business)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await settle(tester);

      expect(find.text('250 kg'), findsOneWidget); // current capacity shown

      await tester.enterText(find.byType(TextField), '600');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('Saved.'), findsOneWidget);
      expect(business.currentCapacityKg, 600);
    },
  );

  testWidgets(
    'rejects a zero/invalid capacity without touching the repository',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final business = FakeBusinessRepository(initialCapacityKg: 250);
      final container = ProviderContainer(
        overrides: [businessRepositoryProvider.overrideWithValue(business)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), '0');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('Enter a valid capacity in kg.'), findsOneWidget);
      expect(business.currentCapacityKg, 250);
    },
  );
}
