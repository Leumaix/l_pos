import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leumadepos/core/widgets/app_button.dart';
import 'package:leumadepos/features/customers/application/customer_providers.dart';
import 'package:leumadepos/features/customers/data/customer_repository.dart';
import 'package:leumadepos/features/customers/domain/customer.dart';
import 'package:leumadepos/features/customers/presentation/repayment_sheet.dart';

/// Same landscape-tablet regression shape as
/// test/features/sell/gas_numpad_sheet_test.dart — this sheet shares the
/// exact same display/keypad/button structure (now via KeypadEntryLayout)
/// and had the identical Tier 1 overflow bug before being redesigned.
void main() {
  const customer = Customer(
    id: 'cust-1',
    name: 'Ngozi Eze',
    phone: '08051112222',
    balance: 5000,
  );

  testWidgets('the repayment sheet stays usable at a short, landscape-style '
      'viewport height — the numeric keypad and Record payment button must '
      'never be pushed off-screen and unreachable', (tester) async {
    // The real Itel tablet: 800x1280 physical @ 240dpi (1.5x), landscape.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        customerRepositoryProvider.overrideWithValue(FakeCustomerRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showRepaymentSheet(context, customer: customer),
                child: const Text('open sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Two "Record payment" texts exist (the sheet title and the
    // button label) — scope to the one inside the AppButton.
    final recordPayment = find.descendant(
      of: find.byType(AppButton),
      matching: find.text('Record payment'),
    );
    expect(recordPayment, findsOneWidget);

    await tester.ensureVisible(recordPayment);
    await tester.pumpAndSettle();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final buttonRect = tester.getRect(recordPayment);
    expect(
      buttonRect.bottom,
      lessThanOrEqualTo(screenHeight),
      reason:
          'Record payment sits at y=${buttonRect.bottom} even after '
          'ensureVisible, past the bottom of a ${screenHeight}px-tall '
          'viewport — unreachable by a real touch.',
    );

    await tester.tap(recordPayment);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('open sheet'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
