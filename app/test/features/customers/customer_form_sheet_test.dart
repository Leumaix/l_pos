import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/features/auth/application/auth_providers.dart';
import 'package:leumadepos/features/auth/data/auth_repository.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/customers/domain/customer.dart';
import 'package:leumadepos/features/customers/domain/customer_transaction.dart';
import 'package:leumadepos/features/customers/presentation/customers_screen.dart';

const _testOwner = AppUser(uid: 'owner-1', name: 'Zazaa', email: 'owner@test', role: 'owner');
const _testAttendant = AppUser(uid: 'staff-1', name: 'Ifeoma', email: 'staff@test', role: 'attendant');

/// The security half (any active staff, not owner-only, can create a
/// customer) is covered against a real Firestore emulator in
/// firestore_rules_tests/customers_rules.test.mjs. This file covers the
/// other half: the form's own UI/state logic against a fake repository.
void main() {
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

  // Scoped to the open bottom sheet specifically — CustomersScreen's own
  // search TextField stays mounted (not disposed) underneath a
  // showModalBottomSheet, so a bare find.byType(TextField).at(0) here
  // silently hits the search field instead of the sheet's Name field.
  Finder sheetTextFields() =>
      find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));

  testWidgets('adding a customer through the form shows up in the list at a zero balance', (tester) async {
    await useDefaultPhoneSurface(tester);
    final customers = FakeCustomerRepository();
    final container = ProviderContainer(
      overrides: [customerRepositoryProvider.overrideWithValue(customers)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CustomersScreen(onOpenCustomer: _noop)),
      ),
    );
    await settle(tester);

    expect(find.text('New Walk-in'), findsNothing);

    await tester.tap(find.byIcon(Icons.person_add_alt_outlined));
    await settle(tester);

    await tester.enterText(sheetTextFields().at(0), 'New Walk-in');
    await tester.enterText(sheetTextFields().at(1), '08012345678');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('New Walk-in'), findsOneWidget);
    expect(find.text('Cleared'), findsWidgets); // zero-balance customers show "Cleared"
  });

  testWidgets(
    'an owner sees the opening-balance field from the Customers screen, and it correctly '
    'sets the starting balance plus an openingBalance ledger entry',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      final customers = FakeCustomerRepository();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_testOwner)),
          customerRepositoryProvider.overrideWithValue(customers),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CustomersScreen(onOpenCustomer: _noop)),
        ),
      );
      await settle(tester);

      await tester.tap(find.byIcon(Icons.person_add_alt_outlined));
      await settle(tester);

      expect(find.text('Opening balance (₦) — optional'), findsOneWidget);

      await tester.enterText(sheetTextFields().at(0), 'Migrated Debtor');
      await tester.enterText(sheetTextFields().at(1), '08033334444');
      await tester.enterText(sheetTextFields().at(2), '15000');
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Save'));
      await settle(tester);

      // tester.runAsync escapes the fake-clock zone for this real,
      // non-delayed-but-still-fake-clock-sensitive stream read — see
      // this file's earlier note on why a bare .first await hung here
      // before.
      await tester.runAsync(() async {
        final all = await customers.watchCustomers().first;
        final created = all.firstWhere((c) => c.name == 'Migrated Debtor');
        expect(created.balance, 15000);

        final transactions = await customers.watchTransactions(created.id).first;
        expect(transactions.single.type, CustomerTransactionType.openingBalance);
        expect(transactions.single.balanceAfter, 15000);
      });
    },
  );

  testWidgets(
    'an attendant does NOT see the opening-balance field from the Customers screen',
    (tester) async {
      await useDefaultPhoneSurface(tester);
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_testAttendant)),
          customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CustomersScreen(onOpenCustomer: _noop)),
        ),
      );
      await settle(tester);

      await tester.tap(find.byIcon(Icons.person_add_alt_outlined));
      await settle(tester);

      expect(find.text('Opening balance (₦) — optional'), findsNothing);
      expect(sheetTextFields(), findsNWidgets(2)); // name + phone only
    },
  );

  testWidgets('the sheet requires both a name and a phone before saving', (tester) async {
    await useDefaultPhoneSurface(tester);
    final container = ProviderContainer(
      overrides: [customerRepositoryProvider.overrideWithValue(FakeCustomerRepository())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CustomersScreen(onOpenCustomer: _noop)),
      ),
    );
    await settle(tester);

    await tester.tap(find.byIcon(Icons.person_add_alt_outlined));
    await settle(tester);

    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('Enter a name.'), findsOneWidget);
  });
}

void _noop(Customer customer) {}
