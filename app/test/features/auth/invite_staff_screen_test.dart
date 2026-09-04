import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leumadepos/app.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/fake_auth_repository.dart';
import 'package:leumadepos/features/auth/data/staff_invite_repository.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/sell/application/inventory_providers.dart';
import 'package:leumadepos/features/sell/application/sales_providers.dart';
import 'package:leumadepos/features/sell/data/inventory_repository.dart';
import 'package:leumadepos/features/sell/data/sales_repository.dart';

/// The security half of "add staff in-app" (who can create/read invites,
/// who can create a staff doc from one, role can't be self-chosen) is
/// covered against a real Firestore emulator in
/// firestore_rules_tests/invites_and_staff_rules.test.mjs — Dart widget
/// tests can't exercise real security rules. This file covers the other
/// half: the Invite Staff screen's own UI/state logic against a fake
/// repository (form validation, the pending-invites list, revoke).
Widget _appWithFakes({required FakeStaffInviteRepository invites}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      staffInviteRepositoryProvider.overrideWithValue(invites),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      salesRepositoryProvider.overrideWithValue(FakeSalesRepository()),
      customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
    ],
    child: const LeumadeposApp(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> useDefaultPhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> signInAsChidi(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'chidi@leumadepos.test');
    await tester.pump(const Duration(milliseconds: 10));
    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.tap(find.text('Sign in'));
    await settle(tester);
  }

  testWidgets('owner sees "Invite staff" in the account menu', (tester) async {
    await useDefaultPhoneSurface(tester);
    await tester.pumpWidget(
      _appWithFakes(invites: FakeStaffInviteRepository()),
    );
    await settle(tester);

    await signInAsChidi(tester);
    expect(find.text('Chidi (Owner)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await settle(tester);

    expect(find.text('Invite staff'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
    'an attendant does NOT see "Invite staff" or "Settings" in the account menu',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      await tester.pumpWidget(
        _appWithFakes(invites: FakeStaffInviteRepository()),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'ifeoma@leumadepos.test');
      await tester.pump(const Duration(milliseconds: 10));
      for (final digit in ['1', '1', '1', '1']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.tap(find.text('Sign in'));
      await settle(tester);

      expect(find.text('Ifeoma'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await settle(tester);

      expect(find.text('Invite staff'), findsNothing);
      expect(find.text('Settings'), findsNothing);
      // The account menu itself still works for an attendant — just
      // without the owner-only entry.
      expect(find.text('Verify another staff member'), findsOneWidget);
    },
  );

  testWidgets(
    'creating an invite adds it to the pending list; revoking removes it',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      final invites = FakeStaffInviteRepository();
      await tester.pumpWidget(_appWithFakes(invites: invites));
      await settle(tester);

      await signInAsChidi(tester);
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await settle(tester);
      await tester.tap(find.text('Invite staff'));
      await settle(tester);

      expect(find.text('No pending invites.'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Ngozi');
      await tester.enterText(fields.at(1), 'ngozi@leumadepos.test');
      await tester.pump(const Duration(milliseconds: 10));

      // Attendant is selected by default; leave it and submit.
      await tester.tap(find.text('Send invite'));
      await settle(tester);

      expect(find.text('No pending invites.'), findsNothing);
      expect(find.text('Ngozi'), findsOneWidget);
      expect(find.text('ngozi@leumadepos.test'), findsOneWidget);

      final createdInvites = await invites.pendingInvites();
      expect(createdInvites, hasLength(1));
      expect(createdInvites.single.role, 'attendant');

      await tester.tap(find.byIcon(Icons.close));
      await settle(tester);

      expect(find.text('No pending invites.'), findsOneWidget);
      expect(await invites.pendingInvites(), isEmpty);
    },
  );

  testWidgets('choosing the Owner role sends an owner-role invite', (
    tester,
  ) async {
    await useDefaultPhoneSurface(tester);
    final invites = FakeStaffInviteRepository();
    await tester.pumpWidget(_appWithFakes(invites: invites));
    await settle(tester);

    await signInAsChidi(tester);
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await settle(tester);
    await tester.tap(find.text('Invite staff'));
    await settle(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Emeka');
    await tester.enterText(fields.at(1), 'emeka@leumadepos.test');
    await tester.pump(const Duration(milliseconds: 10));

    await tester.tap(find.text('Owner'));
    await tester.pump();
    await tester.tap(find.text('Send invite'));
    await settle(tester);

    final createdInvites = await invites.pendingInvites();
    expect(createdInvites, hasLength(1));
    expect(createdInvites.single.role, 'owner');
  });
}
